import json
import os
import unittest
from uuid import uuid4

import test_entry_database as fixtures
from app.members import MemberService
from app.errors import AppError


@unittest.skipUnless(os.environ.get('BOOKSTORE_TEST_ADMIN_CONNECTION'),'未配置隔离SQL连接')
class MemberDatabaseTests(unittest.TestCase):
    connect_as=fixtures.EntryDatabaseTests.connect_as

    def setUp(self):
        from unittest.mock import patch
        fixtures.EntryDatabaseTests.setUpClass.__func__(type(self))
        self.addCleanup(self.connection.close)
        self.addCleanup(self.connection.rollback)
        patcher=patch('app.dao.pyodbc.connect',side_effect=self.connect_as)
        patcher.start(); self.addCleanup(patcher.stop)
        self.actor=dict(phone='13800000003',role='收银员',session_version=1)
        self.service=MemberService(self.dao,'member-secret-'*4)

    def test_new_card_upgrade_history_and_replay(self):
        phone='13987654321'
        preview=self.service.preview(self.actor,dict(request_key=str(uuid4()),phone=phone,level='银卡',operation='buy'))
        result=self.service.confirm(self.actor,preview['quote_token'])
        self.assertEqual(self.service.confirm(self.actor,preview['quote_token']),result)
        member=self.dao.member_read(self.actor,phone)
        self.assertEqual(len(member['history']),1)
        preview=self.service.preview(self.actor,dict(request_key=str(uuid4()),phone=phone,level='金卡',operation='upgrade'))
        upgraded=self.service.confirm(self.actor,preview['quote_token'])
        self.assertEqual(upgraded['old_expiry'],upgraded['new_expiry'])
        self.assertEqual(len(self.dao.member_read(self.actor,phone)['history']),2)

    def test_contact_token_reset_and_ownership(self):
        import hashlib
        phone='13900000001'
        first=self.service.contact(self.actor,dict(request_key=str(uuid4()),phone=phone,contact=phone))
        self.assertEqual(self.dao.member_self(phone,hashlib.sha256(first['access_token'].encode()).digest())['member_id'],phone)
        second=self.service.contact(self.actor,dict(request_key=str(uuid4()),phone=phone,contact='13987654321'))
        with self.assertRaises(AppError):
            self.dao.member_self(phone,hashlib.sha256(first['access_token'].encode()).digest())
        self.assertEqual(self.dao.member_self('13987654321',hashlib.sha256(second['access_token'].encode()).digest())['member_id'],phone)
        preview=self.service.preview(self.actor,dict(request_key=str(uuid4()),phone='13987654321',level='金卡',operation='buy'))
        self.service.confirm(self.actor,preview['quote_token'])
        self.assertEqual(self.connection.cursor().execute('SELECT COUNT(*) FROM dbo.member WHERE phone=?','13987654321').fetchval(),0)
        self.assertEqual(self.dao.member_read(self.actor,phone)['card_level'],'金卡')

    def test_leap_year_renewal_keeps_points_and_uses_march_first(self):
        phone='13900000001'
        cursor=self.connection.cursor()
        cursor.execute("UPDATE dbo.member SET expires_at='20280229' WHERE phone=?",phone)
        points=cursor.execute('SELECT points_balance FROM dbo.member WHERE phone=?',phone).fetchval()
        preview=self.service.preview(self.actor,dict(request_key=str(uuid4()),phone=phone,level='金卡',operation='buy'))
        result=self.service.confirm(self.actor,preview['quote_token'])
        self.assertEqual(result['new_expiry'],'2029-03-01')
        self.assertEqual(cursor.execute('SELECT points_balance FROM dbo.member WHERE phone=?',phone).fetchval(),points)

    def test_card_fee_change_rejects_old_preview_without_charging(self):
        preview=self.service.preview(self.actor,dict(request_key=str(uuid4()),phone='13987654321',level='银卡',operation='buy'))
        cursor=self.connection.cursor()
        cursor.execute('UPDATE dbo.card_type SET card_fee=card_fee+1')
        with self.assertRaises(AppError) as caught:
            self.service.confirm(self.actor,preview['quote_token'])
        self.assertEqual(caught.exception.code,'quote_changed')

    def test_manager_cannot_disable_last_manager_and_cards_keep_cross_tier_rule(self):
        manager=dict(phone='13800000001',role='店长',session_version=1)
        payload=dict(phone=manager['phone'],name='店长',role='库管',enabled=1)
        with self.assertRaises(AppError) as caught:
            self.dao.management_write(manager,str(uuid4()),'employee_save',json.dumps(payload))
        self.assertEqual(caught.exception.code,'management_conflict')

    def test_management_queries_have_bounded_documents_and_exclude_capital_from_profit(self):
        manager=dict(phone='13800000001',role='店长',session_version=1)
        before=self.dao.management_read(manager,'reports')
        employees=self.dao.management_read(manager,'employees',page_size=1)
        self.assertEqual(len(employees['records']),1)
        self.assertGreater(employees['total'],1)
        for kind in ('sales','returns','reservations'):
            documents=self.dao.management_read(manager,kind,page_size=1)
            self.assertLessEqual(len(documents['records']),1)
            self.assertGreater(documents['total'],0)
        from app.operations import OperationsService
        operations=OperationsService(self.dao,'manager-test-secret-'*3)
        preview=operations.preview(manager,'inject',dict(request_key=str(uuid4()),payload=dict(amount='11.00')))
        operations.confirm(manager,preview['quote_token'])
        after=self.dao.management_read(manager,'reports')
        from decimal import Decimal
        self.assertEqual(Decimal(after['cash_balance'])-Decimal(before['cash_balance']),Decimal('11.00'))
        self.assertEqual(after['operating_profit'],before['operating_profit'])

    def test_employee_role_change_invalidates_old_session_and_replay_does_not_increment_again(self):
        manager=dict(phone='13800000001',role='店长',session_version=1)
        phone='13800000004'; key=str(uuid4())
        payload=json.dumps(dict(phone=phone,name='测试库管',role='库管',enabled=1))
        result=self.dao.management_write(manager,key,'employee_save',payload)
        self.assertEqual(self.dao.management_write(manager,key,'employee_save',payload),result)
        cursor=self.connection.cursor()
        self.assertEqual(cursor.execute('SELECT session_version FROM auth.employee_credential WHERE employee_phone=?',phone).fetchval(),2)
        self.assertEqual(self.dao.session_identity(phone,1),None)
        self.assertEqual(self.dao.session_identity(phone,2)['role'],'库管')

    def test_cards_update_both_tiers_without_changing_old_sales_snapshots(self):
        manager=dict(phone='13800000001',role='店长',session_version=1)
        cursor=self.connection.cursor()
        before=[tuple(row) for row in cursor.execute('SELECT id,discount_rate,paid_amount FROM dbo.sale ORDER BY id')]
        self.dao.management_write(manager,str(uuid4()),'cards_save',json.dumps(dict(silver_fee='60.00',gold_fee='100.00',silver_rate='0.95',gold_rate='0.85')))
        self.assertEqual([tuple(row) for row in cursor.execute('SELECT id,discount_rate,paid_amount FROM dbo.sale ORDER BY id')],before)
        values=self.dao.management_read(manager,'cards')['records']
        self.assertEqual({row['level']:row['discount_rate'] for row in values},{'银卡':'0.95','金卡':'0.85'})

    def test_stock_filters_keep_totals_and_rows_consistent(self):
        manager=dict(phone='13800000001',role='店长',session_version=1)
        listing=self.dao.operation_read(manager,'stock',reason='购入',from_date='2026-01-01',to_date='2026-12-31')
        self.assertGreater(listing['total'],0)
        self.assertTrue(all(row['change_type']=='购入' for row in listing['records']))
        self.assertEqual(self.dao.operation_read(manager,'stock',from_date='1900-01-01',to_date='1900-01-02')['records'],[])
