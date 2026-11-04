import os
import json
import unittest
from uuid import uuid4
from decimal import Decimal
from unittest.mock import patch

import test_entry_database as fixture
from app.returns import ReturnService


@unittest.skipUnless(os.environ.get('BOOKSTORE_TEST_ADMIN_CONNECTION'),'未配置隔离SQL连接')
class ReturnDatabaseTests(unittest.TestCase):
    connect_as=fixture.EntryDatabaseTests.connect_as

    def setUp(self):
        fixture.EntryDatabaseTests.setUpClass.__func__(type(self))
        self.addCleanup(self.connection.close); self.addCleanup(self.connection.rollback)
        patcher=patch('app.dao.pyodbc.connect',side_effect=self.connect_as); patcher.start(); self.addCleanup(patcher.stop)
        self.actor=dict(phone='13800000003',role='收银员',session_version=1)
        self.inventory=dict(phone='13800000002',role='库管',session_version=1)
        self.service=ReturnService(self.dao,'return-secret-'*4)

    def test_full_return_reconciles_money_points_and_separate_recovery(self):
        cursor=self.connection.cursor()
        sale=cursor.execute("SELECT TOP(1) id,no,paid_amount,member_phone FROM dbo.sale WHERE status=N'已付' AND subtotal_amount>0 ORDER BY id").fetchone()
        lines=[dict(sale_item_id=row[0],quantity=row[1]) for row in cursor.execute('SELECT id,quantity FROM dbo.sale_item WHERE sale_id=?',sale[0])]
        before=[tuple(row) for row in cursor.execute('SELECT id,stock_total FROM dbo.goods ORDER BY id')]
        preview=self.service.preview(self.actor,dict(request_key=str(uuid4()),no=sale[1],items=lines))
        result=self.service.confirm(self.actor,preview['quote_token'])
        self.assertEqual(Decimal(result['refund_amount']),sale[2])
        self.assertEqual(self.service.confirm(self.actor,preview['quote_token']),result)
        self.assertEqual([tuple(row) for row in cursor.execute('SELECT id,stock_total FROM dbo.goods ORDER BY id')],before)
        for row in cursor.execute('SELECT id FROM dbo.goods_return_item WHERE return_id=?',result['return_id']).fetchall():
            key=str(uuid4()); recovered=self.dao.return_recover(self.inventory,key,row[0])
            self.assertEqual(self.dao.return_recover(self.inventory,key,row[0]),recovered)
        self.assertEqual(cursor.execute('SELECT status FROM dbo.sale WHERE id=?',sale[0]).fetchval(),'已全退')
        self.assertEqual(cursor.execute('SELECT SUM(refund_amount) FROM dbo.goods_return_item WHERE return_id=?',result['return_id']).fetchval(),sale[2])

    def test_refund_distribution_is_stable_for_reordered_input(self):
        cursor=self.connection.cursor()
        sale=cursor.execute("SELECT TOP(1) s.id,s.no FROM dbo.sale s JOIN dbo.sale_item i ON i.sale_id=s.id WHERE s.status=N'已付' AND s.subtotal_amount>0 GROUP BY s.id,s.no HAVING COUNT(*)>1 ORDER BY s.id").fetchone()
        self.assertIsNotNone(sale,'样例须有多行销售以检查顺序独立性')
        lines=[dict(sale_item_id=row[0],quantity=1) for row in cursor.execute('SELECT id FROM dbo.sale_item WHERE sale_id=? ORDER BY id',sale[0])]
        first=self.service.preview(self.actor,dict(request_key=str(uuid4()),no=sale[1],items=lines))['quote']
        second=self.service.preview(self.actor,dict(request_key=str(uuid4()),no=sale[1],items=list(reversed(lines))))['quote']
        first.pop('confirmation_expires_at'); second.pop('confirmation_expires_at')
        self.assertEqual(first,second)
        self.assertEqual(sum(Decimal(str(row['refund_amount'])) for row in first['items']),Decimal(first['refund_amount']))

    def test_repeated_partial_returns_reconcile_original_paid_amount_and_points(self):
        cursor=self.connection.cursor()
        sale=cursor.execute("SELECT TOP(1) s.id,s.no,s.paid_amount FROM dbo.sale s WHERE s.status=N'已付' AND s.subtotal_amount>0 AND EXISTS(SELECT 1 FROM dbo.sale_item i WHERE i.sale_id=s.id AND i.quantity>1) ORDER BY s.id").fetchone()
        self.assertIsNotNone(sale)
        earned=cursor.execute("SELECT COALESCE(SUM(points),0) FROM dbo.point_movement WHERE sale_id=? AND change_type=N'消费获得'",sale[0]).fetchval()
        total=Decimal('0')
        for line,quantity in cursor.execute('SELECT id,quantity FROM dbo.sale_item WHERE sale_id=? ORDER BY id',sale[0]).fetchall():
            for _ in range(quantity):
                preview=self.service.preview(self.actor,dict(request_key=str(uuid4()),no=sale[1],items=[dict(sale_item_id=line,quantity=1)]))
                result=self.service.confirm(self.actor,preview['quote_token'])
                total+=Decimal(result['refund_amount'])
                self.assertEqual(sum(Decimal(str(item['refund_amount'])) for item in result['items']),Decimal(result['refund_amount']))
        self.assertEqual(total,sale[2])
        self.assertEqual(cursor.execute("SELECT -COALESCE(SUM(points),0) FROM dbo.point_movement WHERE sale_id=? AND change_type=N'退货回滚'",sale[0]).fetchval(),earned)
        self.assertEqual(cursor.execute('SELECT status FROM dbo.sale WHERE id=?',sale[0]).fetchval(),'已全退')
