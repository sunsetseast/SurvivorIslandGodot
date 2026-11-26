"""Generate rollback-only SQL tests from intentionally private Godot fixtures.
Run in the isolated local test DB before the verified development project. Never commit output.
"""
import argparse,copy,hashlib,json
from pathlib import Path
from uuid import uuid4

def literal(value):
    return "'" + value.replace("'", "''") + "'"
def wire(envelope):
    payload=json.dumps(envelope,ensure_ascii=False,separators=(',',':'))
    return json.dumps({'payload':payload,'sha256':hashlib.sha256(payload.encode()).hexdigest()},ensure_ascii=False,separators=(',',':'))
def generate(stage):
    raw={name:(stage/name).read_text() for name in ['tribes-2.json','tribes-3.json','technical.json']}
    base=json.loads(json.loads(raw['tribes-2.json'])['payload'])
    def mutated(change):
        envelope=copy.deepcopy(base);change(envelope['state']);return wire(envelope)
    actor=str(base['state']['configuration']['selected'])
    other=next(k for k in base['state']['world']['tonsai']['people'] if k!=actor)
    enemy=next(k for k,p in base['state']['roster'].items() if p['location']!='tonsai')
    invalid={
      'rating':mutated(lambda s:s['roster'][actor]['attributes'].__setitem__('strength',0)),
      'defaults':mutated(lambda s:s['roster'][actor]['state'].__setitem__('health',-1)),
      'ownership':mutated(lambda s:s['roster'][actor].__setitem__('owner','f'*32)),
      'extra-human':mutated(lambda s:s['roster'][other].__setitem__('controller','human')),
      'membership':mutated(lambda s:s['configuration']['tribes'][0]['members'].__setitem__(0,s['configuration']['tribes'][1]['members'][0])),
      'missing':mutated(lambda s:s['roster'].pop(other)),
      'tribe-name':mutated(lambda s:s['configuration']['tribes'][0].__setitem__('name','Unknown')),
      'colors':mutated(lambda s:[s['configuration']['tribes'][i].__setitem__('color',c) for i,c in enumerate(['red','orange'])]),
      'location':mutated(lambda s:s['configuration']['tribes'][0].__setitem__('location','elsewhere')),
      'journal':mutated(lambda s:s['world']['tonsai']['people'][actor]['journal'][0].__setitem__('with',enemy)),
      'rng':mutated(lambda s:s.__setitem__('rng_state','00')),
      'pose':mutated(lambda s:s.__setitem__('pose',{'location':'tonsai','position':[999,0,0],'heading':0,'yaw':0,'pitch':0,'underwater':False})),
      'config-seed-type':mutated(lambda s:s['configuration'].__setitem__('seed',42)),
      'controlled-type':mutated(lambda s:s.__setitem__('controlled',11)),
      'season-type':mutated(lambda s:s.__setitem__('season_id',int('2'*32))),
      'receipt-with-type':mutated(lambda s:s['world']['tonsai']['people'][actor]['journal'][0].__setitem__('with',int(other))),
      'receipt-id-type':mutated(lambda s:s['world']['tonsai']['people'][actor]['journal'][0].__setitem__('id',int('1'*32))),
      'catalog':mutated(lambda s:s['configuration'].__setitem__('catalog','gameplay-v1:'+'0'*64)),
      'controlled':mutated(lambda s:s.__setitem__('controlled','explorer')),
    }
    uid_a,uid_b,sess_a,sess_b=[str(uuid4()) for _ in range(4)]
    sid1,sid2,sid3,sid4=[str(uuid4()) for _ in range(4)]
    statements=['begin;',f"insert into auth.users(id,email_confirmed_at) values ('{uid_a}',now()),('{uid_b}',now());",f"insert into auth.sessions(id,user_id) values ('{sess_a}','{uid_a}'),('{sess_b}','{uid_b}');",'set local role authenticated;']
    def claims(uid,sess):
        statements.append("select set_config('request.jwt.claims',"+literal(json.dumps({'sub':uid,'session_id':sess,'role':'authenticated'}))+",true);")
    def rpc(action,args):
        return 'public.player_data('+literal(action)+','+literal(json.dumps(args,ensure_ascii=False))+'::jsonb)'
    checks=0
    def check(expr,label):
        nonlocal checks
        checks+=1
        statements.append('do $test$ begin if ('+expr+') is not true then raise exception '+literal(label)+'; end if; end $test$;')
    def put(sid,snapshot,expected=0,guest=False):
        return rpc('put',{'id':sid,'expected':expected,'operation':str(uuid4()),'snapshot':snapshot,'guest_import':guest})
    claims(uid_a,sess_a)
    check("not has_table_privilege('authenticated','survivor_private.gameplay_catalogs','select')",'No client catalog access')
    check("not has_function_privilege('authenticated','survivor_private.checked_configurable_snapshot(text)','execute')",'No direct private validator access')
    check(put(sid1,raw['tribes-2.json'])+"->>'status'='saved'",'Two-tribe account create')
    check(rpc('get',{'id':sid1})+"->>'snapshot'="+literal(raw['tribes-2.json']),'Two-tribe exact restore')
    check(put(sid1,raw['tribes-2.json'])+"->>'status'='conflict'",'Revision conflict')
    update=put(sid1,raw['tribes-2.json'],1)
    check(update+"->>'status'='saved'",'Account update')
    check(update+"->>'revision'='2'",'Idempotent retry retains revision')
    for label,snapshot in invalid.items():
        check(put(str(uuid4()),snapshot)+"->>'status'='invalid_snapshot'",'Reject '+label)
    frozen=mutated(lambda s:s['configuration'].__setitem__('information','Immersive'))
    check(put(sid1,frozen,2)+"->>'status'='invalid_snapshot'",'Confirmed configuration immutable')
    check(put(sid2,raw['tribes-3.json'],guest=True)+"->>'status'='saved'",'Explicit three-tribe guest import')
    check(rpc('get',{'id':sid2})+"->>'snapshot'="+literal(raw['tribes-3.json']),'Three-tribe exact restore')
    check(put(str(uuid4()),raw['tribes-3.json'],guest=True)+"->>'status'='already_imported'",'No duplicate guest import')
    check(put(sid3,raw['technical.json'])+"->>'status'='saved'",'Legacy technical create')
    check(rpc('get',{'id':sid3})+"->>'snapshot'="+literal(raw['technical.json']),'Legacy exact restore')
    check(put(str(uuid4()),raw['tribes-2.json'])+"->>'status'='capacity'",'Existing quota retained')
    check("not has_function_privilege('anon','public.player_data(text,jsonb)','execute')",'Anonymous RPC access denied')
    claims(uid_b,sess_b)
    check(rpc('list',{})+"='[]'::jsonb",'Account B isolated list')
    check(rpc('get',{'id':sid1})+"->>'status'='missing'",'Cross-account read rejected')
    check(put(sid1,raw['tribes-2.json'])+"->>'status'='missing'",'Cross-account write rejected')
    check(put(sid4,raw['tribes-2.json'],guest=True)+"->>'status'='saved'",'Import into own empty account slot')
    claims(uid_a,sess_a)
    check(rpc('get',{'id':sid4})+"->>'status'='missing'",'Reverse account isolation')
    statements += ['reset role;', 'rollback;',f"select '{checks} focused RPC checks passed; all test data rolled back' as result;"]
    return '\n'.join(statements)+'\n'
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('private_stage',type=Path);parser.add_argument('output',type=Path)
    args=parser.parse_args();args.output.write_text(generate(args.private_stage))
