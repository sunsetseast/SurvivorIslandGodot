"""Rollback-only v2 validator/RPC regressions using isolated synthetic fixtures."""
import argparse, copy, json, re
from pathlib import Path
from uuid import uuid4
from configurable_rpc import literal, wire

def generate(stage, migration):
    definitions = json.loads((stage/'supply_definitions.json').read_text())
    generated = json.loads(re.search(r"definitions constant jsonb := '(.*?)';", migration.read_text(), re.S)[1])
    assert generated == definitions, 'SQL definition projection drifted from MarooningSupplyCatalog'
    raw = {p.stem:p.read_text() for p in stage.glob('opening-*.json')}
    base = json.loads(json.loads(raw['opening-2-own'])['payload'])
    own = base['state']['roster'][base['state']['controlled']]['tribe']
    def mutated(fn):
        e=copy.deepcopy(base);fn(e['state']);return wire(e)
    invalid={
        'missing-disposition':mutated(lambda s:s['opening_history']['dispositions'].pop('rice-00')),
        'extra-disposition':mutated(lambda s:s['opening_history']['dispositions'].__setitem__('rice-99',s['opening_history']['dispositions']['rice-00'])),
        'quantity':mutated(lambda s:s['tribal_inventory'][own]['rice-00'].__setitem__('quantity',21)),
        'unit':mutated(lambda s:s['tribal_inventory'][own]['rice-00'].__setitem__('unit','litre')),
        'catalog-ref':mutated(lambda s:s['tribal_inventory'][own]['rice-00'].__setitem__('definition_version',2)),
        'original-mass':mutated(lambda s:s['opening_history']['dispositions']['rice-00'].__setitem__('mass_kg',99)),
        'ownership':mutated(lambda s:s['opening_history']['dispositions']['rice-00'].__setitem__('tribe','tonsai')),
        'undelivered':mutated(lambda s:s['opening_history']['transport'][own]['delivered_ids'].clear()),
        'not-arrived':mutated(lambda s:s['opening_history']['contestants']['1'].__setitem__('arrived',False)),
        'reward-double':mutated(lambda s:s['tribal_inventory'][own].__setitem__('reward-copy',s['tribal_inventory'][own]['fishing-equipment-preview'])),
        'rng-precision':mutated(lambda s:s['opening_history'].__setitem__('supply_rng_state',1)),
        'rng-canonical':mutated(lambda s:s['opening_history'].__setitem__('travel_rng_state','00')),
        'first-impressions':mutated(lambda s:s['initialization'].__setitem__('first_impressions_complete',True)),
        'fire':mutated(lambda s:s['world']['tonsai']['objects']['fire'].__setitem__('lit',True)),
        'shelter':mutated(lambda s:s['world']['tonsai']['objects']['shelter'].__setitem__('construction_level',4)),
        'witness-fact':mutated(lambda s:s['opening_history'].__setitem__('witness_semantics','confirmed')),
        'witness-id':mutated(lambda s:s['opening_history']['events'][0]['witness_candidates'].append('99')),
        'events-bound':mutated(lambda s:s['opening_history'].__setitem__('events',[s['opening_history']['events'][0]]*2049)),
        'history-extra':mutated(lambda s:s['opening_history'].__setitem__('nodes',{})),
        'downgrade-fields':mutated(lambda s:s.__setitem__('ruleset_version',1)),
    }
    sql=['begin;']; count=0
    def check(expr,label):
        nonlocal count
        count+=1
        sql.append('do $test$ begin if ('+expr+') is not true then raise exception '+literal(label)+'; end if; end $test$;')
    for name,snapshot in raw.items():
        check('survivor_private.checked_snapshot('+literal(snapshot)+') is not null','Accept '+name)
    check('survivor_private.checked_snapshot('+literal('x'*256001)+') is null','Cloud byte limit unchanged')
    for label,snapshot in invalid.items():
        check('survivor_private.checked_snapshot('+literal(snapshot)+') is null','Reject '+label)
    a,b,sa,sb=[str(uuid4()) for _ in range(4)]
    sid1,sid2=[str(uuid4()) for _ in range(2)]
    sql += [f"insert into auth.users(id,email_confirmed_at) values ('{a}',now()),('{b}',now());",f"insert into auth.sessions(id,user_id) values ('{sa}','{a}'),('{sb}','{b}');",'set local role authenticated;']
    def claims(uid,sess):
        sql.append("select set_config('request.jwt.claims',"+literal(json.dumps({'sub':uid,'session_id':sess,'role':'authenticated'}))+",true);")
    def rpc(action,args):
        return 'public.player_data('+literal(action)+','+literal(json.dumps(args))+ '::jsonb)'
    def put(sid,snapshot,rev=0):
        return rpc('put',{'id':sid,'snapshot':snapshot,'expected':rev,'operation':str(uuid4())})
    claims(a,sa)
    check(put(sid1,raw['opening-2-own'])+"->>'status'='saved'",'V2 create')
    check(rpc('get',{'id':sid1})+"->>'snapshot'="+literal(raw['opening-2-own']),'V2 exact readback')
    update=put(sid1,raw['opening-2-own'],1)
    check(update+"->>'revision'='2'",'V2 revision')
    check(update+"->>'revision'='2'",'V2 idempotent retry')
    legacy=copy.deepcopy(base)
    legacy['state']['ruleset_version']=1
    for key in ['initialization','inventory_version','tribal_inventory','opening_history']:legacy['state'].pop(key)
    check(put(sid1,wire(legacy),2)+"->>'status'='invalid'",'Old client cannot downgrade v2')
    changed=mutated(lambda s:s['opening_history']['contestants']['1'].__setitem__('fatigue','0.5'))
    check(put(sid1,changed,2)+"->>'status'='invalid'",'Immutable opening history')
    check(put(sid2,raw['opening-3-rival'])+"->>'status'='saved'",'V2 three-tribe create')
    check("not has_function_privilege('authenticated','survivor_private.checked_opening_v2(jsonb)','execute')",'Private validator inaccessible')
    claims(b,sb)
    check(rpc('get',{'id':sid1})+"->>'status'='missing'",'V2 account read isolation')
    check(put(sid1,raw['opening-2-own'])+"->>'status'='missing'",'V2 account write isolation')
    sql += ['reset role;','rollback;',f"select '{count} opening validator/RPC checks passed; rolled back' as result;"]
    return '\n'.join(sql)+'\n'
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('stage',type=Path);p.add_argument('migration',type=Path);p.add_argument('output',type=Path);a=p.parse_args();a.output.write_text(generate(a.stage,a.migration))
