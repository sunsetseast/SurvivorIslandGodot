-- Configurable v2 only. No production application is part of this migration.
-- The v1 validator, account RPC, RLS, quotas, revisions and operation IDs remain intact.
alter function survivor_private.checked_configurable_snapshot(text) rename to checked_configurable_snapshot_v1;
alter table survivor_private.save_revisions drop constraint save_revisions_ruleset_version_check;
alter table survivor_private.save_revisions add constraint save_revisions_ruleset_version_check check (ruleset_version in (1,2));

create function survivor_private.opening_number(v jsonb, lo numeric, hi numeric) returns boolean
language sql immutable set search_path = '' as $$
    select coalesce(jsonb_typeof(v) = 'number' and v::text::numeric between lo and hi, false)
$$;

create function survivor_private.opening_metric(v jsonb, lo numeric, hi numeric) returns boolean
language sql immutable set search_path = '' as $$
    select coalesce(jsonb_typeof(v) = 'string' and length(v #>> '{}') <= 32
        and (v #>> '{}') ~ '^-?(0|[1-9][0-9]*)([.][0-9]{1,9})?$'
        and (v #>> '{}')::numeric between lo and hi, false)
$$;

create function survivor_private.checked_opening_v2(s jsonb) returns boolean
language plpgsql immutable set search_path = '' as $$
declare
    -- Generated from MarooningSupplyCatalog.definitions(), definition version 1.
    -- The isolated fixture test asserts this projection against the production catalog.
    definitions constant jsonb := '{"bamboo":{"count":4,"mass_kg":18.0,"quantity":4,"unit":"pole"},"basket":{"count":4,"mass_kg":0.6,"quantity":1,"unit":"basket"},"blanket":{"count":2,"mass_kg":1.2,"quantity":1,"unit":"blanket"},"coconut":{"count":6,"mass_kg":4.5,"quantity":3,"unit":"fruit"},"cup":{"count":3,"mass_kg":0.9,"quantity":3,"unit":"cup"},"fishing":{"count":2,"mass_kg":1.2,"quantity":1,"unit":"kit"},"fruit":{"count":3,"mass_kg":6.0,"quantity":1,"unit":"basket"},"machete":{"count":2,"mass_kg":0.7,"quantity":1,"unit":"tool"},"pot":{"count":3,"mass_kg":2.5,"quantity":1,"unit":"pot"},"rice":{"count":3,"mass_kg":20.5,"quantity":20,"unit":"kg"},"rope":{"count":6,"mass_kg":1.0,"quantity":10,"unit":"metre"},"tarp":{"count":2,"mass_kg":3.0,"quantity":1,"unit":"tarp"},"tools":{"count":2,"mass_kg":3.5,"quantity":1,"unit":"kit"},"water":{"count":4,"mass_kg":10.7,"quantity":10,"unit":"litre"},"wood":{"count":4,"mass_kg":12.0,"quantity":5,"unit":"log"}}';
    h jsonb := s->'opening_history';
    config jsonb := s->'configuration';
    own text := s #>> array['roster', s->>'controlled', 'tribe'];
    expected jsonb := '{}';
    membership jsonb := '{}';
    tribe jsonb;
    row jsonb;
    d jsonb;
    r jsonb;
    e jsonb;
    item jsonb;
    witness jsonb;
    point jsonb;
    id text;
    kind text;
    key text;
    t text;
    n integer;
    seen text[];
    delivered text[];
    observed boolean;
    prior_at numeric := 0;
    elapsed numeric;
begin
    if (s->'inventory_version' = '1' and s->'initialization' = '{"source":"marooning-v2","day":1,"tick":0,"first_impressions_complete":false,"rng_stream":"camp-v1"}'::jsonb
        and jsonb_typeof(s->'tribal_inventory') = 'object' and jsonb_typeof(h) = 'object'
        and h->'version' = '1' and h->>'witness_semantics' = 'proximity_candidates_only'
        and survivor_private.opening_metric(h->'elapsed',0,86400)
        and jsonb_typeof(h->'supply_rng_state') = 'string' and (h->>'supply_rng_state')::bigint::text = h->>'supply_rng_state'
        and jsonb_typeof(h->'travel_rng_state') = 'string' and (h->>'travel_rng_state')::bigint::text = h->>'travel_rng_state') is not true then return false; end if;
    if (select count(*) from jsonb_object_keys(h)) <> 12 then return false; end if;
    elapsed := (h->>'elapsed')::numeric;
    foreach key in array array['dispositions','contestants','contributions','transport','reward'] loop
        if jsonb_typeof(h->key) is distinct from 'object' then return false; end if;
    end loop;
    if (select count(*) from jsonb_object_keys(h->'dispositions')) <> 50
        or (select count(*) from jsonb_object_keys(h->'contestants')) <> 18
        or (select count(*) from jsonb_object_keys(h->'contributions')) <> 18
        or (select count(*) from jsonb_object_keys(h->'transport')) <> jsonb_array_length(config->'tribes')
        or (select count(*) from jsonb_object_keys(s->'tribal_inventory')) <> jsonb_array_length(config->'tribes') then return false; end if;
    for tribe in select value from jsonb_array_elements(config->'tribes') loop
        t := tribe->>'id';
        expected := expected || jsonb_build_object(t,'{}'::jsonb);
        for id in select value::text from jsonb_array_elements(tribe->'members') loop
            membership := membership || jsonb_build_object(id,t);
        end loop;
    end loop;
    for kind,d in select * from jsonb_each(definitions) loop
        for n in 0..(d->>'count')::integer-1 loop
            id := kind || '-' || lpad(n::text,2,'0');
            row := h->'dispositions'->id;
            if (jsonb_typeof(row) = 'object' and row->>'type' = kind
                and row->'quantity' = d->'quantity' and row->'unit' = d->'unit' and row->'mass_kg' = d->'mass_kg'
                and row->'definition_version' = '1' and survivor_private.checkpoint_integer(row->'state',0,5) is not null
                and jsonb_typeof(row->'actor') = 'string' and (row->>'actor' = '0' or membership ? (row->>'actor'))
                and jsonb_typeof(row->'unloader') = 'string' and (row->>'unloader' = '0' or membership ? (row->>'unloader'))
                and row->>'location' in ('ship','loading','raft','carried','shore')
                and survivor_private.opening_metric(row->'secured_at',-1,elapsed)) is not true then return false; end if;
            if (select count(*) from jsonb_object_keys(row)) <> 11 then return false; end if;
            if row->'state' = '4' then
                t := row->>'tribe';
                if (expected ? t and row->>'actor' = '0' and (row->>'secured_at')::numeric >= 0
                    and (row->>'unloader' = '0' or membership->>(row->>'unloader') = t)
                    and (t <> own or row->>'location' = 'shore')) is not true then return false; end if;
                item := jsonb_build_object('type',kind,'quantity',d->'quantity','unit',d->'unit','source','marooning','definition_version',1);
                expected := jsonb_set(expected,array[t,id],item);
            elsif (row->>'tribe' = '' and ((row->'state' = '1') = (row->>'actor' <> '0'))) is not true then return false; end if;
        end loop;
    end loop;
    for id,t in select member.key,member.value #>> '{}' from jsonb_each(membership) as member loop
        row := h->'contestants'->id;
        r := h->'contributions'->id;
        if (jsonb_typeof(row) = 'object' and row->>'tribe' = t
            and jsonb_typeof(row->'arrived') = 'boolean' and jsonb_typeof(row->'recovered') = 'boolean'
            and survivor_private.opening_metric(row->'fatigue',0,1)
            and survivor_private.opening_metric(row->'arrival_time',-1,elapsed)
            and survivor_private.opening_metric(row->'left_deck_at',-1,elapsed)
            and ((row->'arrived' = 'true') = ((row->>'arrival_time')::numeric >= 0))
            and (t <> own or row->'arrived' = 'true') and jsonb_typeof(r) = 'object') is not true then return false; end if;
        if (select count(*) from jsonb_object_keys(row)) <> 18 or (select count(*) from jsonb_object_keys(r)) > 64 then return false; end if;
        foreach key in array array['strokes','perfect','good','missed','boardings','departures','unloaded_count'] loop
            if survivor_private.checkpoint_integer(row->key,0,1000000) is null then return false; end if;
        end loop;
        foreach key in array array['swim_distance','force_total','impulse_total_ns','impulse_delivered_ns','impulse_cancelled_ns'] loop
            if not survivor_private.opening_metric(row->key,0,1000000000000) then return false; end if;
        end loop;
        for key,item in select * from jsonb_each(r) loop
            if length(key) > 64 or survivor_private.checkpoint_integer(item,0,1000000) is null then return false; end if;
        end loop;
    end loop;
    for tribe in select value from jsonb_array_elements(config->'tribes') loop
        t := tribe->>'id'; row := h->'transport'->t;
        if (jsonb_typeof(row) = 'object' and jsonb_typeof(row->'arrived') = 'boolean'
            and survivor_private.opening_metric(row->'arrival_time',-1,elapsed)
            and survivor_private.opening_metric(row->'launch_time',-1,elapsed)
            and ((row->'arrived' = 'true') = ((row->>'arrival_time')::numeric >= 0))
            and row->>'launch_reason' in ('','collection_closed','crew_encouraged','crew_ready')
            and jsonb_typeof(row->'delivered_ids') = 'array' and row->>'resolution' in ('observed','abstract_transport')
            and row->>'state' in ('moored','underway','grounded','regrouped') and row->>'cargo_location' in ('raft','shore')
            and (t <> own or (row->>'state' = 'regrouped' and row->>'cargo_location' = 'shore'))) is not true then return false; end if;
        if (select count(*) from jsonb_object_keys(row)) <> 8 then return false; end if;
        delivered := array[]::text[];
        for item in select value from jsonb_array_elements(row->'delivered_ids') loop
            id := item #>> '{}';
            if (jsonb_typeof(item) = 'string' and expected->t ? id and not id = any(delivered)
                and h #>> array['dispositions',id,'location'] = 'shore') is not true then return false; end if;
            delivered := array_append(delivered,id);
        end loop;
        observed := row->'arrived' = 'true' and cardinality(delivered) = (select count(*) from jsonb_object_keys(expected->t));
        for id in select value::text from jsonb_array_elements(tribe->'members') loop
            observed := observed and h #> array['contestants',id,'arrived'] = 'true';
        end loop;
        if ((row->>'resolution' = 'observed') = observed and (t <> own or observed)) is not true then return false; end if;
        r := s #> array['world',tribe->>'location','objects'];
        if (jsonb_typeof(r->'fire') = 'object' and jsonb_typeof(r->'shelter') = 'object'
            and survivor_private.checkpoint_integer(r #> '{fire,construction_level}',0,3) is not null
            and survivor_private.checkpoint_integer(r #> '{shelter,construction_level}',0,4) is not null
            and (r #> '{fire,lit}' <> 'true' or r #> '{fire,construction_level}' <> '0')) is not true then return false; end if;
        if (select count(*) from jsonb_object_keys(r)) <> 2 or (select count(*) from jsonb_object_keys(r->'fire')) <> 2 or (select count(*) from jsonb_object_keys(r->'shelter')) <> 1 then return false; end if;
        if s->'tick' = '0' and r <> '{"fire":{"lit":false,"construction_level":0},"shelter":{"construction_level":0}}'::jsonb then return false; end if;
    end loop;
    r := h->'reward';
    if (r->>'id' = 'fishing-equipment-preview' and r->>'status' in ('claimed','unclaimed') and r->'mass_kg' = '8'
        and survivor_private.opening_metric(r->'time',0,elapsed) and jsonb_typeof(r->'secured') = 'boolean'
        and jsonb_typeof(r->'actor') = 'string' and (r->>'actor' = '0' or membership ? (r->>'actor'))
        and jsonb_typeof(r->'carrier') = 'string' and (r->>'carrier' = '0' or membership ? (r->>'carrier'))) is not true then return false; end if;
    if (select count(*) from jsonb_object_keys(r)) <> 10 then return false; end if;
    if r->>'status' = 'unclaimed' then
        if (r->>'tribe' = '' and r->>'actor' = '0' and r->>'carrier' = '0' and r->'secured' = 'false'
            and r->>'location' = 'unclaimed' and r->>'method' = '') is not true then return false; end if;
    else
        t := r->>'tribe';
        if (expected ? t and r->>'actor' <> '0' and membership->>(r->>'actor') = t and r->>'method' in ('raft','swim')
            and r->>'location' in ('raft','carried','shore')
            and (r->>'carrier' = '0' or membership->>(r->>'carrier') = t)
            and ((r->>'location' = 'carried') = (r->>'carrier' <> '0'))
            and (r->'secured' = 'true' or r->>'location' = 'carried')
            and (t <> own or (r->'secured' = 'true' and r->>'location' = 'shore'))) is not true then return false; end if;
        if r->'secured' = 'true' then
            expected := jsonb_set(expected,array[t,'fishing-equipment-preview'],'{"type":"offshore_fishing_reward","quantity":1,"unit":"package","source":"offshore_reward","definition_version":1}');
        end if;
    end if;
    for t,r in select * from jsonb_each(expected) loop
        row := s->'tribal_inventory'->t;
        if jsonb_typeof(row) is distinct from 'object' then return false; end if;
        if (select count(*) from jsonb_object_keys(row)) <> (select count(*) from jsonb_object_keys(r)) then return false; end if;
        for id,item in select * from jsonb_each(r) loop
            if not survivor_private.opening_number(row->id->'quantity',0,(item->>'quantity')::numeric)
                or ((row->id) - 'quantity') is distinct from (item - 'quantity') then return false; end if;
        end loop;
    end loop;
    if jsonb_typeof(h->'events') is distinct from 'array' or jsonb_array_length(h->'events') > 2048
        or jsonb_typeof(h->'recoveries') is distinct from 'array' or jsonb_array_length(h->'recoveries') > 128 then return false; end if;
    for e in select value from jsonb_array_elements(h->'events') loop
        if (e->>'source' in ('supplies','travel') and survivor_private.opening_metric(e->'at',prior_at,elapsed)
            and jsonb_typeof(e->'actor') = 'string' and membership ? (e->>'actor')
            and jsonb_typeof(e->'action') = 'string' and length(e->>'action') between 1 and 64
            and jsonb_typeof(e->'witness_candidates') = 'array' and jsonb_array_length(e->'witness_candidates') <= 17) is not true then return false; end if;
        if (select count(*) from jsonb_object_keys(e)) <> (case when e->>'source' = 'supplies' then 8 else 5 end) then return false; end if;
        prior_at := (e->>'at')::numeric;
        seen := array[]::text[];
        for witness in select value from jsonb_array_elements(e->'witness_candidates') loop
            id := witness #>> '{}';
            if (jsonb_typeof(witness) = 'string' and membership ? id and id <> e->>'actor' and not id = any(seen)) is not true then return false; end if;
            seen := array_append(seen,id);
        end loop;
        if e->>'source' = 'supplies' and (h->'dispositions' ? (e->>'instance') and jsonb_typeof(e->'outcome') = 'string'
            and length(e->>'outcome') <= 64 and jsonb_typeof(e->'victim') = 'string'
            and (e->>'victim' = '0' or membership ? (e->>'victim'))) is not true then return false; end if;
    end loop;
    for e in select value from jsonb_array_elements(h->'recoveries') loop
        if (jsonb_typeof(e) = 'object' and jsonb_typeof(e->'actor') = 'string' and membership ? (e->>'actor')
            and survivor_private.opening_metric(e->'at',0,elapsed) and jsonb_typeof(e->'reason') = 'string' and length(e->>'reason') <= 128
            and survivor_private.checkpoint_integer(e->'attempts',0,10000) is not null
            and e->'objective_awarded' = 'false' and jsonb_typeof(e->'reward_carrier') = 'boolean'
            and jsonb_typeof(e->'ordinary_cargo_set_down') = 'string' and jsonb_typeof(e->'secured_batch') = 'array'
            and (e->>'ordinary_cargo_set_down' = '' or h->'dispositions' ? (e->>'ordinary_cargo_set_down'))) is not true then return false; end if;
        if (select count(*) from jsonb_object_keys(e)) <> 10 then return false; end if;
        for item in select value from jsonb_array_elements(e->'secured_batch') loop
            if (jsonb_typeof(item) = 'string' and h #>> array['dispositions',item #>> '{}','tribe'] = membership->>(e->>'actor')) is not true then return false; end if;
        end loop;
        foreach key in array array['from','to'] loop
            if jsonb_typeof(e->key) is distinct from 'array' or jsonb_array_length(e->key) <> 3 then return false; end if;
            for point in select value from jsonb_array_elements(e->key) loop
                if not survivor_private.opening_metric(point,-10000,10000) then return false; end if;
            end loop;
        end loop;
    end loop;
    return true;
exception when data_exception then return false;
end;
$$;

create function survivor_private.checked_configurable_snapshot(raw text) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
    wrapper jsonb; envelope jsonb; s jsonb; v1 jsonb; payload text;
begin
    if raw is null or octet_length(raw) > 256000 then return null; end if;
    wrapper := raw::jsonb;
    if (jsonb_typeof(wrapper->'payload') = 'string' and wrapper->>'sha256' = encode(sha256(convert_to(wrapper->>'payload','UTF8')),'hex')) is not true then return null; end if;
    envelope := (wrapper->>'payload')::jsonb; s := envelope->'state';
    if s->'ruleset_version' = '1' then
        if s ?| array['inventory_version','tribal_inventory','opening_history','initialization'] then return null; end if;
        return survivor_private.checked_configurable_snapshot_v1(raw);
    end if;
    if s->'ruleset_version' is distinct from '2'::jsonb or not survivor_private.checked_opening_v2(s) then return null; end if;
    -- Reuse canonical roster/configuration, pose, scheduler and envelope checks.
    v1 := jsonb_set(envelope,'{state,ruleset_version}','1');
    payload := v1::text;
    if survivor_private.checked_configurable_snapshot_v1(jsonb_build_object('payload',payload,'sha256',encode(sha256(convert_to(payload,'UTF8')),'hex'))::text) is null then return null; end if;
    return envelope;
exception when data_exception then return null;
end;
$$;

-- Old clients may validate a v1 payload themselves. Fence v2 histories at storage
-- too, without changing the authenticated RPC's locking or idempotency behavior.
create function survivor_private.fence_opening_revision() returns trigger
language plpgsql set search_path = '' as $$
declare previous jsonb; current_state jsonb;
begin
    select ((r.snapshot::jsonb->>'payload')::jsonb)->'state' into previous
        from survivor_private.save_revisions r where r.save_id = new.save_id and r.revision = new.revision - 1;
    if previous->'ruleset_version' = '2' then
        current_state := ((new.snapshot::jsonb->>'payload')::jsonb)->'state';
        if current_state->'ruleset_version' is distinct from '2'::jsonb
            or current_state->'opening_history' is distinct from previous->'opening_history'
            or current_state->'initialization' is distinct from previous->'initialization' then
            raise sqlstate '22000' using message = 'opening_history_immutable';
        end if;
    end if;
    return new;
end;
$$;
create trigger fence_opening_revision before insert on survivor_private.save_revisions
    for each row execute function survivor_private.fence_opening_revision();
revoke all on function survivor_private.opening_metric(jsonb,numeric,numeric), survivor_private.opening_number(jsonb,numeric,numeric), survivor_private.checked_opening_v2(jsonb),
    survivor_private.checked_configurable_snapshot(text), survivor_private.checked_configurable_snapshot_v1(text),
    survivor_private.fence_opening_revision() from public, anon, authenticated, service_role;
