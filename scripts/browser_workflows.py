"""Write demo workflows only in a new, explicitly named WebDemo copy."""
import argparse
import json
import re
from pathlib import Path


def main():
    from playwright.sync_api import sync_playwright
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--credentials',required=True)
    parser.add_argument('--output',required=True)
    parser.add_argument('--port',type=int,default=5091)
    args=parser.parse_args()
    credentials=json.loads(Path(args.credentials).read_text(encoding='utf-8'))
    if not credentials['database'].startswith('ShiguangBookstoreWeek7WebDemo'):
        parser.error('Only dedicated WebDemo copies are allowed')
    output=Path(args.output); output.mkdir(parents=True,exist_ok=True)
    base=f'http://127.0.0.1:{args.port}'
    results=[]
    with sync_playwright() as driver:
        browser=driver.chromium.launch(channel='msedge',headless=True)
        contexts=[]
        def page_for(role=None):
            context=browser.new_context(viewport=dict(width=1440,height=1000)); contexts.append(context)
            page=context.new_page()
            if role:
                employee=next(row for row in credentials['employees'] if row['role']==role)
                page.goto(base+'/auth/login')
                page.locator('[name=phone]').fill(employee['phone'])
                page.locator('[name=password]').fill(employee['password'])
                page.get_by_role('button',name='登录',exact=True).click()
                page.wait_for_url(base+'/')
            return page
        def visit(page,path):
            response=page.goto(base+path)
            assert response.status==200,(path,response.status)
        def click(page,label):
            page.get_by_role('button',name=label,exact=True).click()
            assert not page.locator('main [role=alert]').count(),page.locator('main').inner_text()
        def snapshot(page,name):
            if name in {'04-reservation','09-cancellation'}:
                page.locator('main strong').evaluate_all("elements => elements.forEach(element => element.textContent='凭证已隐藏')")
            page.screenshot(path=str(output/(name+'.png')),full_page=True)
            results.append(dict(workflow=name,url=page.url.replace(base,''),status='PASS'))
        try:
            manager=page_for('店长'); inventory=page_for('库管'); cashier=page_for('收银员'); guest=page_for()
            visit(manager,'/management/finance')
            manager.locator('[name=amount]').fill('1000.00'); click(manager,'预览注资'); click(manager,'确认店长注资')
            snapshot(manager,'01-injection')
            visit(inventory,'/purchases'); inventory.locator('[name=supplier_id]').fill('2'); click(inventory,'建立空草稿')
            purchase=inventory.url.replace(base,'')
            inventory.locator('[name=goods_id_0]').fill('3'); inventory.locator('[name=quantity_0]').fill('2'); inventory.locator('[name=unit_cost_0]').fill('5.00')
            click(inventory,'保存草稿明细'); click(inventory,'确认提交申请')
            visit(manager,purchase); click(manager,'确认批准采购'); click(manager,'预览采购付款'); click(manager,'确认采购付款')
            visit(inventory,purchase); click(inventory,'确认整单收货'); snapshot(inventory,'02-purchase-received')
            visit(cashier,'/members'); form=cashier.locator('form[action="/members/preview"]')
            form.locator('[name=phone]').fill('13987650001'); click(cashier,'预览办理收费'); click(cashier,'确认收到款项并办理')
            snapshot(cashier,'03-member-card')
            visit(cashier,'/members?phone=13987650001'); click(cashier,'确认已现场核验，保存并重发凭证')
            token=cashier.locator('main strong').inner_text()
            visit(guest,'/shop/reservations/new'); guest.locator('[name=phone]').fill('13987650001'); guest.locator('[name=quantity_3]').fill('1')
            click(guest,'确认预订，不收款'); code=guest.locator('main strong').inner_text()
            snapshot(guest,'04-reservation')
            visit(cashier,'/pickups'); cashier.locator('[name=phone]').fill('13987650001'); cashier.locator('[name=code]').fill(code)
            cashier.locator('[name=member_phone]').fill('13987650001'); click(cashier,'核验并预览整单收款'); click(cashier,'确认收款并整单交付')
            sale=re.search(r'/sales/([^/]+)$',cashier.url).group(1); snapshot(cashier,'05-pickup-sale')
            visit(cashier,'/returns/new?no='+sale)
            cashier.locator('input[name^=quantity_]').fill('1'); click(cashier,'预览退款'); click(cashier,'确认退款并登记退货')
            return_no=re.search(r'W7R[0-9]+',cashier.locator('h1').inner_text()).group(0); snapshot(cashier,'06-refund')
            visit(inventory,'/return-recovery')
            row=inventory.locator('tr').filter(has_text=return_no)
            row.get_by_role('button',name='确认已足量回收').click(); snapshot(inventory,'07-recovery')
            visit(guest,'/shop/member'); guest.locator('[name=contact]').fill('13987650001'); guest.locator('[name=access_token]').fill(token)
            click(guest,'核验并查询本人记录'); assert sale in guest.locator('main').inner_text()
            # Avoid screenshots of self-service credentials or reservation codes.
            guest.locator('[name=access_token]').fill(''); snapshot(guest,'08-member-self')
            visit(guest,'/shop/reservations/new'); guest.locator('[name=phone]').fill('13987650002'); guest.locator('[name=quantity_3]').fill('1')
            click(guest,'确认预订，不收款'); click(guest,'确认取消整单'); assert '已取消' in guest.locator('main').inner_text()
            snapshot(guest,'09-cancellation')
            visit(manager,'/management/finance'); manager.locator('[name=amount]').fill('1.00'); click(manager,'预览提现'); click(manager,'确认店长提现')
            snapshot(manager,'10-withdrawal')
            visit(manager,'/management/reports'); snapshot(manager,'11-reports')
        finally:
            for context in contexts: context.close()
            browser.close()
            (output/'results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(dict(workflows=len(results),status='PASS'),ensure_ascii=False))


if __name__=='__main__': main()
