"""在仓库根目录运行：验证当前HTTP销售页面及预览，不提交销售。"""
import json
import re
from http.cookiejar import CookieJar
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import HTTPCookieProcessor, build_opener


base = 'http://127.0.0.1:5000'
employees = json.loads(Path('app/demo-credentials.local.json').read_text(encoding='utf-8'))['employees']


def hidden(page, name):
    return re.search(r'name="'+name+r'" value="([^"]+)"', page).group(1)


for employee in employees:
    client = build_opener(HTTPCookieProcessor(CookieJar()))
    with client.open(base+'/auth/login', timeout=10) as response:
        page = response.read().decode('utf-8')
    body = urlencode(dict(phone=employee['phone'], password=employee['password'], csrf_token=hidden(page,'csrf_token'))).encode('utf-8')
    with client.open(base+'/auth/login', data=body, timeout=10) as response:
        assert response.status == 200
        assert employee['name'] in response.read().decode('utf-8')
    if employee['role'] != '收银员':
        try:
            client.open(base+'/sales/new', timeout=10)
        except HTTPError as error:
            assert error.code == 403
            error.close()
        else:
            raise AssertionError('Noncashier was allowed to enter sales')
        print(f"employee {employee['phone']}: sales role denial PASS")
        continue
    with client.open(base+'/sales/new', timeout=10) as response:
        page = response.read().decode('utf-8')
        assert response.status == 200
    with client.open(base+'/api/sale-goods', timeout=10) as response:
        catalog = json.load(response)['data']
    item = next(row for row in catalog if row['on_shelf'] and row['available_qty']>0)
    body = urlencode({'quantity_'+str(item['id']):1, 'member_phone':'', 'used_points':0,
                      'request_key':hidden(page,'request_key'), 'csrf_token':hidden(page,'csrf_token')}).encode('utf-8')
    with client.open(base+'/sales/preview', data=body, timeout=10) as response:
        page = response.read().decode('utf-8')
        assert response.status == 200
        assert '确认已收款并生成销售单' in page
        assert item['name'] in page
    print(f"employee {employee['phone']}: catalog, form and signed preview PASS; no sale submitted")
