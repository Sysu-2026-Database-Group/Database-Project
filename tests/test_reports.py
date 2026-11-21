"""Product ranking report: public quantity access, role fallback and manager metrics."""
import unittest
from datetime import date, timedelta

from app import create_app
from test_web import WorkspaceDAO


class RankingDAO(WorkspaceDAO):
    def __init__(self):
        super().__init__()
        self.rank_calls = []
        self.cumulative_calls = []
        self.moving_calls = []
        self.moving_rows = [
            dict(sale_date='2026-09-28', daily_net_quantity=1,
                 daily_net_revenue='10.00', moving_avg_3d_quantity='1.00',
                 moving_avg_3d_revenue='10.00'),
            dict(sale_date='2026-09-29', daily_net_quantity=2,
                 daily_net_revenue='20.00', moving_avg_3d_quantity='1.50',
                 moving_avg_3d_revenue='15.00'),
            dict(sale_date='2026-09-30', daily_net_quantity=3,
                 daily_net_revenue='30.00', moving_avg_3d_quantity='2.00',
                 moving_avg_3d_revenue='20.00'),
        ]

    def product_sales_rank(self, connection, from_date, to_date, metric):
        self.rank_calls.append((connection, from_date, to_date, metric))
        return [dict(goods_id=3, goods_name='测试商品', net_quantity=2,
                     gross_sales_amount='38.00', net_revenue='17.05',
                     total_orders=2, returned_orders=1,
                     metric_rank=1, display_order=1)]

    def cumulative_sales_by_date(self, from_date, to_date):
        self.cumulative_calls.append(('date', from_date, to_date))
        return [dict(sold_date='2026-09-01', daily_net_quantity=2,
                     daily_net_revenue='17.05', cumulative_net_quantity=2,
                     cumulative_net_revenue='17.05')]

    def cumulative_sales_by_product(self, from_date, to_date):
        self.cumulative_calls.append(('product', from_date, to_date))
        return [dict(goods_id=3, goods_name='测试商品', net_quantity=2,
                     net_revenue='17.05', cumulative_net_quantity=2,
                     cumulative_net_revenue='17.05')]

    def moving_average_sales(self, as_of_date):
        self.moving_calls.append(as_of_date)
        return self.moving_rows


class ProductRankingTests(unittest.TestCase):
    def setUp(self):
        self.dao = RankingDAO()
        self.app = create_app(dict(TESTING=True, SECRET_KEY='ranking-secret-' * 3), dao=self.dao)
        self.client = self.app.test_client()

    def login(self, role):
        self.dao.row['role'] = role
        self.client.get('/auth/login')
        with self.client.session_transaction() as stored:
            token = stored['csrf_token']
        response = self.client.post('/auth/login', data=dict(
            phone=self.dao.row['phone'], password='test-password-123', csrf_token=token))
        self.assertEqual(response.status_code, 302)

    def test_guest_sees_quantity_with_default_last_30_days(self):
        response = self.client.get('/reports/product-ranking')
        self.assertEqual(response.status_code, 200)
        self.assertIn('净销量', response.get_data(as_text=True))
        self.assertNotIn('净收入', response.get_data(as_text=True))
        connection, from_date, to_date, metric = self.dao.rank_calls[-1]
        self.assertEqual((connection, metric), ('guest', 'quantity'))
        self.assertEqual((to_date - from_date).days, 29)

    def test_non_manager_revenue_or_orders_falls_back_to_quantity(self):
        for role in ('收银员', '库管'):
            self.login(role)
            for metric in ('revenue', 'orders'):
                response = self.client.get('/reports/product-ranking', query_string=dict(metric=metric))
                self.assertEqual(response.status_code, 200)
                self.assertIn('已按净销量显示', response.get_data(as_text=True))
                self.assertEqual(self.dao.rank_calls[-1][3], 'quantity')

    def test_manager_can_switch_metrics(self):
        self.login('店长')
        for metric in ('quantity', 'revenue', 'orders'):
            response = self.client.get('/reports/product-ranking', query_string=dict(
                metric=metric, from_date='2026-09-01', to_date='2026-09-30'))
            self.assertEqual(response.status_code, 200)
            self.assertEqual(self.dao.rank_calls[-1][1:], (
                date(2026, 9, 1), date(2026, 9, 30), metric))
        self.assertIn('净收入', self.client.get(
            '/reports/product-ranking?metric=revenue').get_data(as_text=True))

    def test_cumulative_sales_is_manager_only(self):
        for role in (None, '收银员', '库管'):
            if role:
                self.login(role)
            response = self.client.get('/reports/cumulative-sales')
            self.assertEqual(response.status_code, 403)

        self.login('店长')
        response = self.client.get('/reports/cumulative-sales')
        self.assertEqual(response.status_code, 200)
        self.assertIn('累计销售', response.get_data(as_text=True))
        self.assertEqual(self.dao.cumulative_calls[-1][0], 'date')

    def test_cumulative_sales_modes_and_defaults(self):
        self.login('店长')
        for mode in ('date', 'product'):
            response = self.client.get('/reports/cumulative-sales', query_string=dict(
                mode=mode, from_date='2026-09-01', to_date='2026-09-30'))
            self.assertEqual(response.status_code, 200)
            self.assertEqual(self.dao.cumulative_calls[-1][0], mode)
            self.assertEqual(self.dao.cumulative_calls[-1][1:], (
                date(2026, 9, 1), date(2026, 9, 30)))

        self.client.get('/reports/cumulative-sales')
        _, from_date, to_date = self.dao.cumulative_calls[-1]
        self.assertEqual((to_date - from_date).days, 29)

    def test_cumulative_sales_rejects_invalid_mode_and_dates(self):
        self.login('店长')
        self.assertEqual(self.client.get(
            '/reports/cumulative-sales?mode=unknown').status_code, 400)
        self.assertEqual(self.client.get(
            '/reports/cumulative-sales?from_date=2026-09-31').status_code, 400)
        self.assertEqual(self.client.get(
            '/reports/cumulative-sales?from_date=2026-09-02&to_date=2026-09-01').status_code, 400)

    def test_moving_average_is_manager_only_and_shows_window(self):
        for role in (None, '收银员', '库管'):
            if role:
                self.login(role)
            self.assertEqual(self.client.get('/reports/moving-average').status_code, 403)

        self.login('店长')
        response = self.client.get('/reports/moving-average?as_of_date=2026-09-30')
        self.assertEqual(response.status_code, 200)
        body = response.get_data(as_text=True)
        self.assertIn('2026-09-28 至 2026-09-30', body)
        self.assertIn('2.00', body)
        self.assertEqual(self.dao.moving_calls[-1], date(2026, 9, 30))

    def test_moving_average_dates_are_validated(self):
        self.login('店长')
        self.assertEqual(self.client.get(
            '/reports/moving-average?as_of_date=2099-01-01').status_code, 400)
        self.assertEqual(self.client.get(
            '/reports/moving-average?as_of_date=2026-09-31').status_code, 400)
        self.assertEqual(self.client.get(
            '/reports/moving-average?as_of_date=0001-01-01').status_code, 400)
        self.client.get('/reports/moving-average')
        self.assertEqual(self.dao.moving_calls[-1], date.today())

    def test_moving_average_zero_window_is_shown_as_zero(self):
        self.login('店长')
        self.dao.moving_rows = [
            dict(sale_date=f'2026-09-{day:02d}', daily_net_quantity=0,
                 daily_net_revenue='0.00', moving_avg_3d_quantity='0.00',
                 moving_avg_3d_revenue='0.00')
            for day in (28, 29, 30)
        ]
        response = self.client.get('/reports/moving-average?as_of_date=2026-09-30')
        body = response.get_data(as_text=True)
        self.assertEqual(response.status_code, 200)
        self.assertIn('该窗口内没有销售数据', body)
        self.assertIn('0.00', body)

    def test_invalid_dates_and_metric_are_controlled(self):
        self.assertEqual(self.client.get(
            '/reports/product-ranking?from_date=2026-09-31').status_code, 400)
        self.assertEqual(self.client.get(
            '/reports/product-ranking?from_date=2026-09-02&to_date=2026-09-01').status_code, 400)
        response = self.client.get('/reports/product-ranking?metric=unknown')
        self.assertEqual(response.status_code, 200)
        self.assertIn('已按净销量显示', response.get_data(as_text=True))
        self.assertEqual(self.dao.rank_calls[-1][3], 'quantity')
