"""Optional real Edge smoke acceptance against an explicitly isolated demo."""
import argparse
import json
from pathlib import Path


def main():
    from playwright.sync_api import sync_playwright
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--credentials', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--port', type=int, default=5091)
    args = parser.parse_args()
    credentials = json.loads(Path(args.credentials).read_text(encoding='utf-8'))
    if not credentials['database'].startswith('ShiguangBookstoreWeek7WebDemo'):
        parser.error('Only a dedicated WebDemo database is allowed')
    output = Path(args.output)
    output.mkdir(parents=True, exist_ok=True)
    records = []
    with sync_playwright() as driver:
        browser = driver.chromium.launch(channel='msedge', headless=True)
        try:
            for width in (360, 1440):
                for role, paths in (
                    (None, ['/shop', '/shop/reservations/new', '/shop/reservations/lookup', '/shop/member']),
                    ('店长', ['/workspace', '/management/finance', '/management/cards', '/management/employees', '/management/reports', '/purchases', '/management/sales', '/management/returns', '/management/reservations']),
                    ('库管', ['/workspace', '/goods', '/suppliers', '/supplier-quotes', '/purchases', '/inventory', '/return-recovery']),
                    ('收银员', ['/workspace', '/sales/new', '/sales', '/pickups', '/members?phone=13900000001', '/returns/new?no=S20260922-W604'])):
                    context = browser.new_context(viewport=dict(width=width, height=1000))
                    page = context.new_page()
                    errors = []
                    page.on('pageerror', lambda error: errors.append(str(error)))
                    if role:
                        employee = next(row for row in credentials['employees'] if row['role'] == role)
                        page.goto(f'http://127.0.0.1:{args.port}/auth/login')
                        page.locator('[name=phone]').fill(employee['phone'])
                        page.locator('[name=password]').fill(employee['password'])
                        page.locator('button[type=submit]').click()
                        page.wait_for_url(f'http://127.0.0.1:{args.port}/')
                    for index, path in enumerate(paths):
                        response = page.goto(f'http://127.0.0.1:{args.port}{path}')
                        page.locator('main h1').first.wait_for()
                        overflow = page.evaluate('document.documentElement.scrollWidth > innerWidth')
                        filename = f'{width}-{role or "guest"}-{index}.png'
                        page.screenshot(path=str(output / filename), full_page=True)
                        record = dict(width=width, role=role, path=path, status=response.status,
                                      overflow=overflow, javascript_errors=list(errors), screenshot=filename)
                        records.append(record)
                    context.close()
        finally:
            browser.close()
    (output / 'results.json').write_text(json.dumps(records, ensure_ascii=False, indent=2), encoding='utf-8')
    failures = [row for row in records if row['status'] != 200 or row['overflow'] or row['javascript_errors']]
    print(json.dumps(dict(pages=len(records), failures=len(failures), details=failures), ensure_ascii=False))
    return bool(failures)


if __name__ == '__main__':
    raise SystemExit(main())
