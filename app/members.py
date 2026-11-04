import base64
import hashlib
import hmac
import json
import re
from uuid import UUID,uuid4

from flask import Blueprint,current_app,render_template,request,session,redirect,url_for
from itsdangerous import URLSafeSerializer,BadData

from .errors import AppError
from .sales import require_cashier

bp=Blueprint('members',__name__)


class MemberService:
    def __init__(self,dao,secret):
        self.dao=dao; self.secret=secret.encode(); self.signer=URLSafeSerializer(secret,salt='member-v1')

    def preview(self,actor,data):
        require_cashier(actor)
        phone=data.get('phone'); level=data.get('level'); operation=data.get('operation')
        try:
            key=str(UUID(data.get('request_key','')))
        except (ValueError,TypeError,AttributeError):
            raise AppError('invalid_member','请求标识不正确。',400) from None
        if not isinstance(phone,str) or not re.fullmatch('[0-9]{11}',phone) or level not in {'银卡','金卡'} or operation not in {'buy','upgrade'}:
            raise AppError('invalid_member','请检查手机号、档位和办理方式。',400)
        quote=self.dao.member_quote(actor,phone,level,operation)
        token=self.signer.dumps(dict(actor=[actor['phone'],actor['session_version']],key=key,phone=phone,level=level,operation=operation,quote=quote))
        return dict(quote=json.loads(quote),quote_token=token)

    def confirm(self,actor,token):
        require_cashier(actor)
        try:
            if not isinstance(token,str) or len(token)>16000: raise BadData('token')
            value=self.signer.loads(token)
            if not isinstance(value,dict) or set(value)!={'actor','key','phone','level','operation','quote'} or value['actor']!=[actor['phone'],actor['session_version']]: raise BadData('actor')
        except BadData:
            raise AppError('invalid_confirmation','会员收费确认无效。',400) from None
        token=base64.urlsafe_b64encode(hmac.new(self.secret,('member-access:'+value['key']).encode(),hashlib.sha256).digest()).decode().rstrip('=')
        result=self.dao.member_create(actor,value['key'],value['phone'],value['level'],value['operation'],value['quote'],hashlib.sha256(token.encode()).digest())
        return dict(result,access_token=token)

    def contact(self,actor,data):
        require_cashier(actor)
        try: key=str(UUID(data.get('request_key','')))
        except (ValueError,TypeError,AttributeError): raise AppError('invalid_member','请求标识不正确。',400) from None
        phone=data.get('phone'); contact=data.get('contact')
        if not isinstance(phone,str) or not isinstance(contact,str) or not re.fullmatch('[0-9]{11}',phone) or not re.fullmatch('[0-9]{11}',contact):
            raise AppError('invalid_member','手机号应为11位数字。',400)
        token=base64.urlsafe_b64encode(hmac.new(self.secret,('member-access:'+key).encode(),hashlib.sha256).digest()).decode().rstrip('=')
        result=self.dao.member_contact(actor,key,phone,contact,hashlib.sha256(token.encode()).digest())
        return dict(result,access_token=token)


def service(): return current_app.extensions['members']


def cashier():
    actor=current_app.extensions['employees'].current_actor(session.get('actor')); require_cashier(actor); return actor


@bp.get('/members')
def page():
    actor=cashier(); phone=request.args.get('phone','')
    member=service().dao.member_read(actor,phone) if re.fullmatch('[0-9]{11}',phone) else None
    return render_template('members.html',actor=actor,member=member,request_key=str(uuid4()),phone=phone)


@bp.post('/members/preview')
def preview():
    actor=cashier(); return render_template('member_preview.html',actor=actor,**service().preview(actor,request.form))


@bp.post('/members')
def confirm():
    actor=cashier(); result=service().confirm(actor,request.form.get('quote_token'))
    return render_template('member_receipt.html',actor=actor,receipt=result)


@bp.post('/members/contact')
def contact():
    actor=cashier(); result=service().contact(actor,request.form)
    return render_template('member_receipt.html',actor=actor,receipt=result)


@bp.get('/shop/member')
def self_form(): return render_template('member_self.html',member=None)


@bp.post('/shop/member')
def self_lookup():
    contact=request.form.get('contact',''); token=request.form.get('access_token','')
    if not re.fullmatch('[0-9]{11}',contact) or not 32<=len(token)<=100:
        raise AppError('invalid_credential','请填写有效联系方式和自助凭证。',400)
    member=service().dao.member_self(contact,hashlib.sha256(token.encode()).digest())
    return render_template('member_self.html',member=member)
