-- ISOLATED CANDIDATE ONLY. Intentionally outside migrations and not wired to RPC.
-- Apply only to a disposable database containing the v2 migration for verification.
-- Production compatibility, storage constraints and synchronization remain disabled.
create function survivor_private.checked_living_camp_v3(s jsonb) returns boolean
language plpgsql stable set search_path = '' as $$
declare
    legacy jsonb := s;
    inventory jsonb := '{}';
    tribe text; id text; site text; k text; kind text; expected_unit text;
    row jsonb; item jsonb; camp jsonb; person jsonb; original jsonb;
    legacy_items jsonb; people jsonb; claims jsonb;
    payload text; envelope jsonb;
    capacities constant jsonb := '{"fire":3,"shelter":6,"shore":4,"spring":3,"trail":3,"work":3}';
    units constant jsonb := '{"rice":"g","water":"ml","coconut":"fruit","fruit":"basket","machete":"tool","pot":"pot","fishing":"kit","tarp":"tarp","rope":"metre","bamboo":"pole","wood":"log","blanket":"blanket","basket":"basket","cup":"cup","tools":"kit","offshore_fishing_reward":"package"}';
    n bigint; amount bigint;
begin
    if s->'ruleset_version' is distinct from '3'::jsonb
        or survivor_private.checkpoint_integer(s->'calendar_seconds',0,40000000000) is null
        or survivor_private.checkpoint_integer(s #> '{transaction_state,sequence}',0,4000000000) is null
        or jsonb_typeof(s->'conditions') is distinct from 'object'
        or (select count(*) from jsonb_object_keys(s->'conditions')) <> 18 then return false; end if;
    if (s->>'day')::bigint <> ((s->>'calendar_seconds')::bigint + 7200) / 86400 + 1 then return false; end if;
    for id,row in select * from jsonb_each(s->'roster') loop
        person := s #> array['conditions',id];
        if jsonb_typeof(person) is distinct from 'object' or (select count(*) from jsonb_object_keys(person)) <> 4 then return false; end if;
        foreach k in array array['nutrition','hydration','energy','health'] loop
            if survivor_private.checkpoint_integer(person->k,0,720000) is null then return false; end if;
        end loop;
    end loop;
    -- Reconstruct only original acquisitions to reuse the complete immutable v2
    -- opening validator. Runtime stock is validated independently below.
    for tribe in select jsonb_object_keys(s->'tribes') loop
        legacy_items := '{}';
        for id,row in select * from jsonb_each(s #> '{opening_history,dispositions}') loop
            if row->>'tribe' = tribe and row->'state' = '4' then
                legacy_items := legacy_items || jsonb_build_object(id,jsonb_build_object('type',row->'type','quantity',row->'quantity','unit',row->'unit','source','marooning','definition_version',1));
            end if;
        end loop;
        row := s #> '{opening_history,reward}';
        if row->>'tribe' = tribe and row->'secured' = 'true' then
            legacy_items := legacy_items || jsonb_build_object('fishing-equipment-preview',jsonb_build_object('type','offshore_fishing_reward','quantity',1,'unit','package','source','offshore_reward','definition_version',1));
        end if;
        inventory := inventory || jsonb_build_object(tribe,legacy_items);
        if jsonb_typeof(s #> array['tribal_inventory',tribe]) is distinct from 'object'
            or (select count(*) from jsonb_object_keys(s #> array['tribal_inventory',tribe])) > 256 then return false; end if;
        for id,item in select * from jsonb_each(s #> array['tribal_inventory',tribe]) loop
            kind := item->>'type'; expected_unit := units->>kind;
            n := survivor_private.checkpoint_integer(item->'acquired_quantity',0,1000000000);
            amount := survivor_private.checkpoint_integer(item->'quantity',0,n);
            if expected_unit is null or n is null or amount is null or item->>'unit' is distinct from expected_unit
                or item->'definition_version' is distinct from '1'::jsonb
                or item->>'source' is null or item->>'source' not in ('marooning','offshore_reward','camp_gameplay','development_fixture') then return false; end if;
            original := legacy_items->id;
            if original is not null then
                if item->'type' is distinct from original->'type' or item->'source' is distinct from original->'source'
                    or n <> (original->>'quantity')::bigint * (case when kind in ('rice','water') then 1000 else 1 end) then return false; end if;
            elsif id !~ '^camp-[0-9a-f]{24}$' then return false; end if;
        end loop;
        if exists (select 1 from jsonb_object_keys(legacy_items) x where not (s #> array['tribal_inventory',tribe]) ? x) then return false; end if;
    end loop;
    if (select count(*) from jsonb_object_keys(s->'tribal_inventory')) <> (select count(*) from jsonb_object_keys(s->'tribes')) then return false; end if;
    if (select count(*) from jsonb_each(s->'tribal_inventory') t cross join lateral jsonb_object_keys(t.value) i) <>
        (select count(distinct i) from jsonb_each(s->'tribal_inventory') t cross join lateral jsonb_object_keys(t.value) i) then return false; end if;
    legacy := jsonb_set(legacy,'{tribal_inventory}',inventory);
    if not survivor_private.checked_opening_v2(legacy) then return false; end if;
    -- Validate shared activity capacities, then neutralize evolving scheduler
    -- fields for reuse of the canonical v1 roster/configuration validator.
    for site,camp in select * from jsonb_each(s->'world') loop
        people := '{}'; claims := '{}';
        for id,person in select * from jsonb_each(camp->'people') loop
            if person->>'stage' is null or person->>'stage' not in ('waiting','travel','occupied')
                or survivor_private.checkpoint_integer(person->'deadline',0,(s->>'tick')::bigint + 600) is null then return false; end if;
            k := person->>'activity';
            if k is null then return false; end if;
            if person->>'stage' = 'waiting' then
                if k <> '' then return false; end if;
            else
                if not capacities ? k then return false; end if;
                n := coalesce((claims->>k)::bigint,0) + 1;
                if n > (capacities->>k)::bigint then return false; end if;
                claims := claims || jsonb_build_object(k,n);
            end if;
            people := people || jsonb_build_object(id,person || '{"activity":"","stage":"waiting","deadline":0}'::jsonb);
        end loop;
        legacy := jsonb_set(legacy,array['world',site,'people'],people);
    end loop;
    legacy := jsonb_set(legacy,'{ruleset_version}','1');
    legacy := jsonb_set(legacy,'{day}',to_jsonb((s->>'tick')::bigint / 2400 + 1));
    envelope := jsonb_build_object('schema',2,'game_version','0.3.0','save_revision',1,'timestamp',100,'state',legacy);
    payload := envelope::text;
    return survivor_private.checked_configurable_snapshot_v1(jsonb_build_object('payload',payload,'sha256',encode(sha256(convert_to(payload,'UTF8')),'hex'))::text) is not null;
exception when data_exception then return false;
end;
$$;
revoke all on function survivor_private.checked_living_camp_v3(jsonb) from public, anon, authenticated, service_role;
