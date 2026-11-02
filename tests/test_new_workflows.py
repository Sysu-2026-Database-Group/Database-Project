import json
import unittest
from uuid import uuid4
from unittest.mock import Mock

from app.members import MemberService
from app.reservations import ReservationService
from app.returns import ReturnService
from app.errors import AppError


class WorkflowContractTests(unittest.TestCase):
    def setUp(self):
        self.actor=dict(phone='13800000003',role='收银员',session_version=1)
        self.dao=Mock()

    def test_reservation_unknown_result_retry_preserves_unguessable_code(self):
        service=ReservationService(self.dao,'secret-'*8)
        payload=dict(request_key=str(uuid4()),phone='13912345678',items=[dict(goods_id=3,quantity=2)])
        service.create(payload); first=self.dao.reservation_create.call_args.args
        service.create(payload); self.assertEqual(first,self.dao.reservation_create.call_args.args)
        service.create(dict(payload,request_key=str(uuid4())))
        self.assertNotEqual(first[2],self.dao.reservation_create.call_args.args[2])
        self.assertRegex(first[2],r'^[A-Z2-7]{20}$')

    def test_pickup_confirmation_cannot_be_used_by_another_session(self):
        service=ReservationService(self.dao,'secret-'*8)
        self.dao.pickup_quote.return_value='{"paid_amount":19}'
        value=service.preview(self.actor,dict(request_key=str(uuid4()),phone='13912345678',code='A'*20))
        with self.assertRaises(AppError): service.confirm(dict(self.actor,session_version=2),value['quote_token'])
        self.dao.pickup_create.assert_not_called()
        service.confirm(self.actor,value['quote_token'])
        self.assertEqual(self.dao.pickup_create.call_args.args[2:4],('13912345678','A'*20))

    def test_member_confirmation_and_contact_credentials_bind_to_actor_and_request(self):
        service=MemberService(self.dao,'secret-'*8)
        self.dao.member_quote.return_value='{"amount":"20.00"}'
        preview=service.preview(self.actor,dict(request_key=str(uuid4()),phone='13912345678',level='银卡',operation='buy'))
        with self.assertRaises(AppError): service.confirm(dict(self.actor,session_version=2),preview['quote_token'])
        self.dao.member_create.assert_not_called()
        self.dao.member_contact.return_value=dict(member_phone='13912345678',contact_phone='13912345678')
        payload=dict(request_key=str(uuid4()),phone='13912345678',contact='13912345678')
        first=service.contact(self.actor,payload); second=service.contact(self.actor,payload)
        self.assertEqual(first['access_token'],second['access_token'])
        self.assertNotEqual(first['access_token'],service.contact(self.actor,dict(payload,request_key=str(uuid4())))['access_token'])
        self.assertNotEqual(self.dao.member_contact.call_args.args[-1],first['access_token'])

    def test_return_input_normalizes_order_and_refuses_duplicate_or_overrides(self):
        service=ReturnService(self.dao,'secret-'*8)
        self.dao.return_quote.return_value='{"refund_amount":"5.00"}'
        payload=dict(request_key=str(uuid4()),no='SALE-1',items=[dict(sale_item_id=2,quantity=1),dict(sale_item_id=1,quantity=2)])
        preview=service.preview(self.actor,payload)
        self.assertEqual(json.loads(self.dao.return_quote.call_args.args[-1]),[dict(sale_item_id=1,quantity=2),dict(sale_item_id=2,quantity=1)])
        with self.assertRaises(AppError): service.preview(self.actor,dict(payload,items=[payload['items'][0]]*2))
        with self.assertRaises(AppError): service.confirm(dict(self.actor,session_version=2),preview['quote_token'])
        self.dao.return_create.assert_not_called()
