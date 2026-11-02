import json
import re
from uuid import UUID,uuid4

from flask import Blueprint,current_app,render_template,request,session,redirect,url_for
from itsdangerous import BadData,URLSafeSerializer

from .errors import AppError
from .operations import integer
from .web import pagination

bp=Blueprint('returns',__name__)


class ReturnService:
    def __init__(self,dao,secret): self.dao=dao; self.signer=URLSafeSerializer(secret,salt='return-v1')

    def preview(self,actor,data):
        if actor['role']!='收银员': raise AppError('forbidden','仅收银员受理退款。',403)
        try: key=str(UUID(data.get('request_key','')))
        except (TypeError,ValueError,AttributeError): raise AppError('invalid_return','请求标识不正确。',400) from None
        no=data.get('no'); items=data.get('items')
        if not isinstance(no,str) or not re.fullmatch('[A-Za-z0-9-]{1,20}',no) or not isinstance(items,list) or not 1<=len(items)<=50:
            raise AppError('invalid_return','请填写原单号及退货数量。',400)
        lines=[]; seen=set()
        for item in items:
            if not isinstance(item,dict) or set(item)!={'sale_item_id','quantity'}: raise AppError('invalid_return','退货明细格式错误。',400)
            identifier=integer(item['sale_item_id']); quantity=integer(item['quantity'],maximum=1000)
            if identifier in seen: raise AppError('invalid_return','同一原销售明细不能重复。',400)
            seen.add(identifier); lines.append(dict(sale_item_id=identifier,quantity=quantity))
        raw=json.dumps(sorted(lines,key=lambda line:line['sale_item_id']),sort_keys=True,separators=(',',':'))
        quote=self.dao.return_quote(actor,no,raw)
        token=self.signer.dumps(dict(actor=[actor['phone'],actor['session_version']],key=key,no=no,items=raw,quote=quote))
        return dict(quote=json.loads(quote),quote_token=token)

    def confirm(self,actor,token):
        if actor['role']!='收银员': raise AppError('forbidden','仅收银员受理退款。',403)
        try:
            if not isinstance(token,str) or len(token)>16000: raise BadData('token')
            value=self.signer.loads(token)
            if not isinstance(value,dict) or set(value)!={'actor','key','no','items','quote'} or value['actor']!=[actor['phone'],actor['session_version']]: raise BadData('actor')
        except BadData: raise AppError('invalid_confirmation','退款确认无效，请重新预览。',400) from None
        return self.dao.return_create(actor,value['key'],value['no'],value['items'],value['quote'])


def actor(role):
    value=current_app.extensions['employees'].current_actor(session.get('actor'))
    if value['role']!=role: raise AppError('forbidden','当前岗位不能办理此业务。',403)
    return value


def service(): return current_app.extensions['returns']


@bp.get('/returns/new')
def form():
    current=actor('收银员'); no=request.args.get('no','')
    source=service().dao.return_source(current,no) if no else None
    return render_template('return_form.html',actor=current,source=source,request_key=str(uuid4()))


@bp.post('/returns/preview')
def preview():
    current=actor('收银员'); items=[]
    for key in request.form:
        if key.startswith('quantity_'):
            value=request.form.get(key,'')
            if len(request.form.getlist(key))!=1 or not re.fullmatch('[0-9]+',value): raise AppError('invalid_return','数量应为非负整数。',400)
            if int(value): items.append(dict(sale_item_id=int(key[9:]),quantity=int(value)))
    value=service().preview(current,dict(request_key=request.form.get('request_key'),no=request.form.get('no'),items=items))
    return render_template('return_preview.html',actor=current,**value)


@bp.post('/returns')
def confirm():
    current=actor('收银员'); receipt=service().confirm(current,request.form.get('quote_token'))
    return render_template('return_receipt.html',actor=current,receipt=receipt)


@bp.get('/return-recovery')
def pending():
    current=actor('库管')
    return render_template('return_pending.html',actor=current,listing=service().dao.return_pending(current,**pagination()),request_key=str(uuid4()))


@bp.post('/return-recovery')
def recover():
    current=actor('库管')
    try:
        key=str(UUID(request.form.get('request_key',''))); item=integer(int(request.form.get('return_item_id','')))
    except (TypeError,ValueError,AttributeError): raise AppError('invalid_return','回收请求格式不正确。',400) from None
    service().dao.return_recover(current,key,item)
    return redirect(url_for('returns.pending'),code=303)
