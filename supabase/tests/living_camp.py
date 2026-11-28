"""Generate rollback-only checks for the disconnected Phase 5A SQL candidate."""
import argparse
import copy
import json
from pathlib import Path
from configurable_rpc import literal

parser = argparse.ArgumentParser()
parser.add_argument('fixtures', type=Path)
args = parser.parse_args()
sql = ['begin;']
count = 0

def check(state, expected, label):
    global count
    count += 1
    expression = 'survivor_private.checked_living_camp_v3(' + literal(json.dumps(state)) + '::jsonb)'
    sql.append('do $test$ begin if (' + expression + ') is distinct from ' + str(expected).lower() + ' then raise exception ' + literal(label) + '; end if; end $test$;')

for path in sorted(args.fixtures.glob('living-*.json')):
    state = json.loads(json.loads(path.read_text())['payload'])['state']
    check(state, True, 'accept ' + path.stem)
    for label, change in [
        ('condition', lambda s: s['conditions']['1'].__setitem__('hydration', -1)),
        ('clock', lambda s: s.__setitem__('calendar_seconds', -1)),
        ('day', lambda s: s.__setitem__('day', 99)),
        ('ledger', lambda s: s['transaction_state'].__setitem__('sequence', -1)),
    ]:
        bad = copy.deepcopy(state)
        change(bad)
        check(bad, False, label)
    own = state['roster']['1']['tribe']
    if state['tribal_inventory'][own]:
        instance = next(iter(state['tribal_inventory'][own]))
        bad = copy.deepcopy(state)
        bad['tribal_inventory'][own][instance]['quantity'] = -1
        check(bad, False, 'negative stock')
    # Live RPC remains deliberately incompatible, regardless of candidate acceptance.
    check_state = copy.deepcopy(state)
    check_state['ruleset_version'] = 2
    check(check_state, False, 'unsupported candidate version')
sql += ['rollback;', "select '%d isolated Living Camp checks passed' as result;" % count]
print('\n'.join(sql))
