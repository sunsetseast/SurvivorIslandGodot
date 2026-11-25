-- Godot parses JSON numbers as floats and re-encodes integers as e.g. 42.0.
-- Accept whole JSON numbers without rounding fractions or accepting strings.
create function survivor_private.checkpoint_integer(value jsonb, minimum bigint, maximum bigint)
returns bigint language sql immutable strict set search_path = '' as $$
    select case when jsonb_typeof(value) = 'number' then
        case when value::numeric between minimum and maximum
            and trunc(value::numeric) = value::numeric then (value::numeric)::bigint end
    end;
$$;

revoke all on function survivor_private.checkpoint_integer(jsonb,bigint,bigint) from public, anon, authenticated;

create or replace function survivor_private.checked_snapshot(raw text) returns jsonb
language plpgsql immutable set search_path = '' as $$
declare
    wrapper jsonb;
    envelope jsonb;
    state jsonb;
    location text;
    camp jsonb;
    contestant jsonb;
    person jsonb;
    id text;
    activity text;
    stage text;
    claimed text[];
    receipt jsonb;
    receipts text[];
    roster_index integer;
    tribe text;
    name text;
    pose jsonb;
    coordinate integer;
    tick integer;
    schema_version integer;
begin
    if raw is null or octet_length(raw) > 256000 then return null; end if;
    wrapper := raw::jsonb;
    if (jsonb_typeof(wrapper->'payload') = 'string'
        and wrapper->>'sha256' = encode(sha256(convert_to(wrapper->>'payload', 'UTF8')), 'hex')) is not true
    then return null; end if;
    envelope := (wrapper->>'payload')::jsonb;
    state := envelope->'state';
    tick := survivor_private.checkpoint_integer(state->'tick', 0, 1000000000);
    schema_version := survivor_private.checkpoint_integer(envelope->'schema', 1, 2);
    if (schema_version is not null
        and envelope->>'game_version' ~ '^[0-9]+[.][0-9]+[.][0-9]+$'
        and char_length(envelope->>'game_version') <= 24
        and survivor_private.checkpoint_integer(envelope->'timestamp', 1, 4102444800) is not null
        and survivor_private.checkpoint_integer(envelope->'save_revision', 1, 4000000000) is not null
        and state->>'season_id' ~ '^[0-9a-f]{32}$'
        and state->>'player_id' ~ '^[0-9a-f]{32}$'
        and jsonb_typeof(state->'seed') = 'string'
        and (state->>'seed')::bigint::text = state->>'seed'
        and jsonb_typeof(state->'rng_state') = 'string'
        and (state->>'rng_state')::bigint::text = state->>'rng_state'
        and state->>'ruleset' = 'technical-season'
        and state->'ruleset_version' = '1'::jsonb
        and state->>'phase' = 'camp' and state->>'controlled' = 'explorer'
        and survivor_private.checkpoint_integer(state->'revision', tick, 4000000000) is not null
        and tick is not null and survivor_private.checkpoint_integer(state->'day', 1, 416667) = tick / 2400 + 1
        and state->'tribes' = '{"tribe-1":"tonsai","tribe-2":"camp-2","tribe-3":"camp-3"}'
        and jsonb_typeof(state->'pose') = 'object'
        and jsonb_typeof(state->'roster') = 'object'
        and state #>> '{roster,explorer,owner}' = state->>'player_id'
        and jsonb_typeof(state->'world') = 'object') is not true
    then return null; end if;
    if (select count(*) from jsonb_object_keys(state->'roster')) <> 18
       or (select count(*) from jsonb_object_keys(state->'world')) <> 3
    then return null; end if;
    pose := state->'pose';
    if pose <> '{}' then
        if (pose->>'location' = 'tonsai' and jsonb_typeof(pose->'position') = 'array'
            and jsonb_typeof(pose->'heading') = 'number' and abs((pose->>'heading')::float8) <= pi()
            and jsonb_typeof(pose->'yaw') = 'number' and abs((pose->>'yaw')::float8) <= pi()
            and jsonb_typeof(pose->'pitch') = 'number' and abs((pose->>'pitch')::float8) <= pi() * 0.5
            and (jsonb_typeof(pose->'underwater') = 'boolean' or schema_version = 1)) is not true
        then return null; end if;
        if jsonb_array_length(pose->'position') <> 3 then return null; end if;
        for coordinate in 0..2 loop
            if jsonb_typeof(pose->'position'->coordinate) <> 'number' then return null; end if;
        end loop;
        if ((pose->'position'->>0)::float8 between -83.3 and 135.3
            and (pose->'position'->>1)::float8 between -25 and 80
            and (pose->'position'->>2)::float8 between -62.3 and 124.3) is not true
        then return null; end if;
    end if;
    foreach location in array array['tonsai','camp-2','camp-3'] loop
        tribe := case when location = 'tonsai' then 'tribe-1' else 'tribe-' || right(location, 1) end;
        camp := state->'world'->location;
        if (jsonb_typeof(camp->'people') = 'object'
           and jsonb_typeof(camp #> '{objects,fire,lit}') = 'boolean'
           and survivor_private.checkpoint_integer(camp->'arrivals', 0, 4000000000) is not null) is not true
        then return null; end if;
        if (select count(*) from jsonb_object_keys(camp->'people')) <> 6 then return null; end if;
        claimed := array[]::text[];
        for roster_index in 1..6 loop
            if location = 'tonsai' then
                id := (array['explorer','cirie','yul','parvati','jeremy','kelley'])[roster_index];
                name := initcap(id);
            else
                id := tribe || '-slot-' || roster_index;
                name := 'Technical slot ' || roster_index;
            end if;
            contestant := state->'roster'->id;
            if contestant is distinct from jsonb_build_object(
                'catalog',id,'name',name,'tribe',tribe,'location',location,'status','active',
                'controller',case when id = 'explorer' then 'human' else 'ai' end,
                'owner',case when id = 'explorer' then state->>'player_id' else '' end)
            then return null; end if;
            person := camp->'people'->id;
            activity := person->>'activity';
            stage := person->>'stage';
            if (stage in ('waiting','travel','occupied')
                and survivor_private.checkpoint_integer(person->'deadline', 0, tick + 112) is not null
                and jsonb_typeof(person->'journal') = 'array'
                and jsonb_typeof(person->'activity') = 'string') is not true
            then return null; end if;
            if stage = 'waiting' then
                if activity <> '' then return null; end if;
            else
                if id = 'explorer' or activity not in ('fire','shelter','shore','spring','trail','work')
                    or activity = any(claimed) then return null; end if;
                claimed := array_append(claimed, activity);
            end if;
            if jsonb_array_length(person->'journal') > 500 then return null; end if;
            receipts := array[]::text[];
            for receipt in select value from jsonb_array_elements(person->'journal') loop
                if (receipt->>'id' ~ '^[0-9a-f]{32}$'
                    and survivor_private.checkpoint_integer(receipt->'tick', 0, tick) is not null
                    and receipt->>'with' <> id and camp->'people' ? (receipt->>'with')
                    and receipt->>'topic' in ('camp','water')
                    and jsonb_typeof(receipt->'reply') = 'string' and char_length(receipt->>'reply') <= 512
                    and not (receipt->>'id' = any(receipts))) is not true then return null; end if;
                receipts := array_append(receipts, receipt->>'id');
            end loop;
        end loop;
    end loop;
    -- Normalize only metadata consumed by the RPC. The stored and returned
    -- snapshot is still the original checked text, including its own checksum.
    state := state || jsonb_build_object('tick', tick, 'day', tick / 2400 + 1, 'ruleset_version', 1);
    return envelope || jsonb_build_object('schema', schema_version, 'state', state);
exception when data_exception then
    return null;
end;
$$;
