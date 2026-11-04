import unittest

from app import create_app
from test_auth import MemoryEmployees


class PublicCatalogTests(unittest.TestCase):
    def setUp(self):
        class Catalogue(MemoryEmployees):
            calls = []

            def shop_catalog(self, **filters):
                self.calls.append(filters)
                return dict(page=filters['page'], page_size=filters['page_size'], total=1,
                            records=[dict(id=3, name='阅读与生活', category='文创', price='19.00', available=False,
                                          toy_code='TEST', spec='纸质书签')])
        self.dao = Catalogue()
        self.app = create_app(dict(TESTING=True, SECRET_KEY='public-test-secret-'*3), dao=self.dao)
        self.client = self.app.test_client()

    def test_anonymous_home_catalog_and_detail(self):
        self.assertEqual(self.client.get('/').headers['Location'], '/shop')
        self.assertIn('暂时无货', self.client.get('/shop').text)
        self.assertIn('纸质书签', self.client.get('/shop/goods/3').text)
        self.assertEqual(self.client.get('/api/shop/goods/3').json['data']['price'], '19.00')

    def test_filters_are_bound_and_invalid_pagination_rejected(self):
        self.assertEqual(self.client.get('/api/shop/goods?search=%25&category=文创').status_code, 200)
        self.assertEqual(self.dao.calls[-1]['search'], '%')
        before = len(self.dao.calls)
        for query in ('category=other', 'search=a&search=b', 'page=0', 'page_size=101'):
            self.assertEqual(self.client.get('/api/shop/goods?' + query).status_code, 400)
        self.assertEqual(len(self.dao.calls), before)
