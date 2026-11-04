import json
import re
from decimal import Decimal
from uuid import UUID,uuid4

from flask import Blueprint,current_app,render_template,request,session,redirect,url_for
from werkzeug.security import generate_password_hash

from .errors import AppError
from .operations import money,text
from .web import pagination
from datetime import date

bp=Blueprint('management',__name__)


def actor():
    value=current_app.extensions['employees'].current_actor(session.get('actor'))
    if value['role']!='店长':
        raise AppError('forbidden','仅店长可以办理此业务。',403)
    return value


@bp.get('/management/<kind>')
def page(kind):
    if kind not in {'employees','cards','reports','sales','returns','reservations'}:
        raise AppError('not_found','页面不存在。',404)
    current=actor()
    dates={}
    for name in ('from_date','to_date'):
        raw=request.args.get(name,'')
        try: dates[name]=date.fromisoformat(raw).isoformat() if raw else None
        except ValueError: raise AppError('invalid_date','日期应为 YYYY-MM-DD。',400) from None
    if dates['from_date'] and dates['to_date'] and dates['from_date']>dates['to_date']:
        raise AppError('invalid_date','起始日期不能晚于结束日期。',400)
    value=current_app.extensions['employees'].dao.management_read(current,kind,**pagination(),**dates)
    if kind in {'sales','returns','reservations'}:
        return render_template('management_documents.html',actor=current,kind=kind,data=value)
    return render_template('management.html',actor=current,kind=kind,data=value,request_key=str(uuid4()))


@bp.post('/management/<kind>')
def save(kind):
    current=actor()
    try:
        key=str(UUID(request.form.get('request_key','')))
    except (ValueError,TypeError,AttributeError):
        raise AppError('invalid_management','请求标识不正确。',400) from None
    if kind=='employees':
        phone=request.form.get('phone','')
        role=request.form.get('role')
        enabled=request.form.get('enabled')
        password=request.form.get('password','')
        if not re.fullmatch('[0-9]{11}',phone) or role not in {'店长','收银员','库管'} or enabled not in {'0','1'} or (password and not 12<=len(password)<=256):
            raise AppError('invalid_management','请检查手机号、岗位和密码长度（12至256位）。',400)
        payload=dict(phone=phone,name=text(request.form.get('name'),20),role=role,enabled=int(enabled))
        if password:
            # Stable hash within the same request for unknown-result retries.
            # A per-request salt avoids storing plaintext passwords in request records.
            import hashlib,hmac
            salt=hmac.new(current_app.config['SECRET_KEY'].encode(),('employee:'+key).encode(),hashlib.sha256).hexdigest()
            digest=hashlib.scrypt(password.encode(),salt=salt.encode(),n=32768,r=8,p=1,maxmem=128*1024*1024).hex()
            payload['password_hash']='scrypt:32768:8:1$'+salt+'$'+digest
        action='employee_save'
    elif kind=='cards':
        payload={name:money(request.form.get(name)) for name in ('silver_fee','gold_fee','silver_rate','gold_rate')}
        if Decimal(payload['silver_rate'])>1 or Decimal(payload['gold_rate'])>1:
            raise AppError('invalid_management','折扣率必须大于0且不超过1。',400)
        action='cards_save'
    else:
        raise AppError('not_found','页面不存在。',404)
    current_app.extensions['employees'].dao.management_write(current,key,action,json.dumps(payload,sort_keys=True,separators=(',',':'),ensure_ascii=False))
    return redirect(url_for('management.page',kind=kind),code=303)
