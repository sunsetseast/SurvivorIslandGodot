-- Server-owned gameplay approval data is provisioned separately through private staging.
-- This migration intentionally contains no contestant data or artwork metadata.
create table survivor_private.gameplay_catalogs (
    fingerprint text primary key,
    canonical text not null,
    created_at timestamptz not null default now(),
    check (fingerprint = 'gameplay-v1:' || encode(sha256(convert_to(canonical, 'UTF8')), 'hex')),
    check (jsonb_typeof(canonical::jsonb) = 'array' and jsonb_array_length(canonical::jsonb) = 18),
    check (octet_length(canonical) <= 100000)
);
alter table survivor_private.gameplay_catalogs enable row level security;
revoke all on survivor_private.gameplay_catalogs from public, anon, authenticated, service_role;
create policy rpc_only on survivor_private.gameplay_catalogs as restrictive
    for all to anon, authenticated using (false) with check (false);

-- Keep the original technical validator intact for existing clients and saves.
alter function survivor_private.checked_snapshot(text) rename to checked_technical_snapshot_v1;

create or replace function survivor_private.checked_configurable_snapshot(raw text) returns jsonb
language plpgsql stable set search_path = '' as $$
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
    config jsonb;
    approved jsonb;
    entry jsonb;
    groups integer;
    group_index integer := 0;
    offscreen integer := 2;
    tribe_record jsonb;
    members jsonb;
    member jsonb;
    member_id integer;
    selected_id integer;
    seen text[] := array[]::text[];
    names text[] := array[]::text[];
    colors text[] := array[]::text[];
    expected_roster jsonb := '{}';
    expected_tribes jsonb := '{}';
    expected_locations text[] := array[]::text[];
begin
    if raw is null or octet_length(raw) > 256000 then return null; end if;
    wrapper := raw::jsonb;
    if (jsonb_typeof(wrapper->'payload') = 'string'
        and wrapper->>'sha256' = encode(sha256(convert_to(wrapper->>'payload', 'UTF8')), 'hex')) is not true
    then return null; end if;
    envelope := (wrapper->>'payload')::jsonb;
    state := envelope->'state';
    config := state->'configuration';
    select canonical::jsonb into approved from survivor_private.gameplay_catalogs where fingerprint = config->>'catalog';
    if approved is null or jsonb_typeof(config->'tribes') is distinct from 'array' then return null; end if;
    groups := jsonb_array_length(config->'tribes');
    selected_id := survivor_private.checkpoint_integer(config->'selected', 1, 18);
    if (groups in (2,3) and selected_id is not null
        and config - array['seed','selected','information','catalog','method','tribes'] = '{}'::jsonb
        and jsonb_typeof(config->'seed') = 'string'
        and config->>'seed' = state->>'seed'
        and config->>'information' in ('Detailed','Immersive')
        and config->>'method' in ('Random','Balanced','Manual','Brains / Brawn / Beauty','Battle of the Sexes')
        and (config->>'method' <> 'Brains / Brawn / Beauty' or groups = 3)
        and (config->>'method' <> 'Battle of the Sexes' or groups = 2)) is not true then return null; end if;
    for tribe_record in select value from jsonb_array_elements(config->'tribes') loop
        group_index := group_index + 1;
        tribe := 'tribe-' || group_index;
        members := tribe_record->'members';
        if (jsonb_typeof(members) = 'array' and tribe_record->>'id' = tribe
            and tribe_record->>'name' = any(array['Tagi','Moto','Fang','Bayon','Luvu','Tika','Ratu','Soka','Yanuya','Galang','Salani','Nuku','Manono','Jabeni','Tandang','Zhan Hu','Ikabula','La Mina'])
            and tribe_record->>'color' in ('red','orange','blue','purple','green')
            and not (tribe_record->>'name' = any(names)) and not (tribe_record->>'color' = any(colors))
            and tribe_record->>'label' = case config->>'method'
                when 'Brains / Brawn / Beauty' then (array['Brains','Brawn','Beauty'])[group_index]
                when 'Battle of the Sexes' then (array['Male','Female'])[group_index] else '' end) is not true then return null; end if;
        if jsonb_array_length(members) <> 18 / groups then return null; end if;
        if members is distinct from (select jsonb_agg(value order by value::numeric) from jsonb_array_elements(members)) then return null; end if;
        names := array_append(names, tribe_record->>'name');
        colors := array_append(colors, tribe_record->>'color');
        if members @> jsonb_build_array(selected_id) then location := 'tonsai';
        else location := 'camp-' || offscreen; offscreen := offscreen + 1; end if;
        if tribe_record->>'location' is distinct from location then return null; end if;
        expected_locations := array_append(expected_locations, location);
        expected_tribes := expected_tribes || jsonb_build_object(tribe, location);
        for member in select value from jsonb_array_elements(members) loop
            member_id := survivor_private.checkpoint_integer(member, 1, 18);
            if member_id is null or member_id::text = any(seen) then return null; end if;
            id := member_id::text;
            seen := array_append(seen, id);
            select value into entry from jsonb_array_elements(approved) where value->'id' = to_jsonb(member_id);
            if entry is null then return null; end if;
            if config->>'method' = 'Brains / Brawn / Beauty' and entry->>'trait' is distinct from (array['Mental','Physical','Social'])[group_index] then return null; end if;
            if config->>'method' = 'Battle of the Sexes' and entry->>'gender' is distinct from (array['male','female'])[group_index] then return null; end if;
            expected_roster := expected_roster || jsonb_build_object(id, jsonb_build_object(
                'catalog',member_id,'name',entry->'name','tribe',tribe,'location',location,'status','active',
                'controller',case when member_id = selected_id then 'human' else 'ai' end,
                'owner',case when member_id = selected_id then state->>'player_id' else '' end,
                'attributes',entry->'attributes','state',entry->'defaults'));
        end loop;
    end loop;
    if cardinality(seen) <> 18 or ('red' = any(colors) and 'orange' = any(colors))
        or state->'roster' is distinct from expected_roster or state->'tribes' is distinct from expected_tribes then return null; end if;
    tick := survivor_private.checkpoint_integer(state->'tick', 0, 1000000000);
    schema_version := survivor_private.checkpoint_integer(envelope->'schema', 1, 2);
    if (schema_version is not null
        and envelope->>'game_version' ~ '^[0-9]+[.][0-9]+[.][0-9]+$'
        and char_length(envelope->>'game_version') <= 24
        and survivor_private.checkpoint_integer(envelope->'timestamp', 1, 4102444800) is not null
        and survivor_private.checkpoint_integer(envelope->'save_revision', 1, 4000000000) is not null
        and jsonb_typeof(state->'season_id') = 'string'
        and jsonb_typeof(state->'player_id') = 'string'
        and jsonb_typeof(state->'controlled') = 'string'
        and state->>'season_id' ~ '^[0-9a-f]{32}$'
        and state->>'player_id' ~ '^[0-9a-f]{32}$'
        and jsonb_typeof(state->'seed') = 'string'
        and (state->>'seed')::bigint::text = state->>'seed'
        and jsonb_typeof(state->'rng_state') = 'string'
        and (state->>'rng_state')::bigint::text = state->>'rng_state'
        and state->>'ruleset' = 'configurable-single-player'
        and state->'ruleset_version' = '1'::jsonb
        and state->>'phase' = 'camp' and state->>'controlled' = selected_id::text
        and survivor_private.checkpoint_integer(state->'revision', tick, 4000000000) is not null
        and tick is not null and survivor_private.checkpoint_integer(state->'day', 1, 416667) = tick / 2400 + 1
        and jsonb_typeof(state->'pose') = 'object'
        and jsonb_typeof(state->'roster') = 'object'
        and jsonb_typeof(state->'world') = 'object') is not true
    then return null; end if;
    if (select count(*) from jsonb_object_keys(state->'roster')) <> 18
       or (select count(*) from jsonb_object_keys(state->'world')) <> groups
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
    foreach location in array expected_locations loop
        camp := state->'world'->location;
        if (jsonb_typeof(camp->'people') = 'object'
           and jsonb_typeof(camp #> '{objects,fire,lit}') = 'boolean'
           and survivor_private.checkpoint_integer(camp->'arrivals', 0, 4000000000) is not null) is not true
        then return null; end if;
        if (select count(*) from jsonb_object_keys(camp->'people')) <> 18 / groups then return null; end if;
        claimed := array[]::text[];
        for id in select key from jsonb_each(expected_roster) where value->>'location' = location loop
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
                if id = selected_id::text or activity not in ('fire','shelter','shore','spring','trail','work')
                    or activity = any(claimed) then return null; end if;
                claimed := array_append(claimed, activity);
            end if;
            if jsonb_array_length(person->'journal') > 500 then return null; end if;
            receipts := array[]::text[];
            for receipt in select value from jsonb_array_elements(person->'journal') loop
                if (jsonb_typeof(receipt->'id') = 'string'
                    and jsonb_typeof(receipt->'with') = 'string'
                    and receipt->>'id' ~ '^[0-9a-f]{32}$'
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

create function survivor_private.checked_snapshot(raw text) returns jsonb
language plpgsql stable set search_path = '' as $$
begin
    if raw is null or octet_length(raw) > 256000 then return null; end if;
    if ((raw::jsonb->>'payload')::jsonb #>> '{state,ruleset}') = 'configurable-single-player' then
        return survivor_private.checked_configurable_snapshot(raw);
    end if;
    return survivor_private.checked_technical_snapshot_v1(raw);
exception when data_exception then return null;
end;
$$;
revoke all on function survivor_private.checked_snapshot(text),
    survivor_private.checked_configurable_snapshot(text),
    survivor_private.checked_technical_snapshot_v1(text) from public, anon, authenticated, service_role;

-- Retain the existing authenticated RPC, locks, quotas and optimistic concurrency.
create or replace function survivor_private.player_data(action text, args jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
    player uuid := auth.uid();
    session_id uuid := (auth.jwt()->>'session_id')::uuid;
    selected survivor_private.save_slots;
    previous survivor_private.save_revisions;
    slot_id uuid;
    operation uuid;
    expected integer;
    raw text;
    envelope jsonb;
    state jsonb;
    snapshot_hash text;
    prefs jsonb;
    next_revision integer;
    settings survivor_private.player_settings;
    profile survivor_private.profiles;
    prior_state jsonb;
begin
    if player is null or session_id is null or not exists (
        select 1 from auth.users u join auth.sessions s on s.user_id = u.id
        where u.id = player and u.email_confirmed_at is not null
            and u.deleted_at is null and s.id = session_id
            and (s.not_after is null or s.not_after > now())
    ) then
        raise insufficient_privilege using message = 'session_required';
    end if;
    if action = 'list' then
        return coalesce((select jsonb_agg(survivor_private.save_metadata(s) order by s.updated_at desc)
            from survivor_private.save_slots s where s.account_id = player and s.deleted_at is null), '[]');
    end if;
    if action = 'profile' then
        select * into profile from survivor_private.profiles where account_id = player;
        select * into settings from survivor_private.player_settings where account_id = player;
        return jsonb_build_object('display_name', coalesce(profile.display_name, 'Explorer'),
            'preferences', settings.preferences, 'settings_revision', coalesce(settings.revision, 0));
    end if;

    -- Serialize per-account mutations, including quota and idempotency checks.
    if action in ('put', 'delete', 'name', 'settings') then
        perform pg_advisory_xact_lock(hashtextextended(player::text, 740913));
        perform 1 from auth.users u where u.id = player and u.deleted_at is null for key share;
        if not found then raise insufficient_privilege using message = 'session_required'; end if;
    end if;
    if action = 'name' then
        raw := btrim(args->>'name');
        if raw is null or char_length(raw) not between 1 and 40 or raw ~ '[[:cntrl:]]'
        then return jsonb_build_object('status','invalid'); end if;
        insert into survivor_private.profiles(account_id, display_name) values (player, raw)
            on conflict (account_id) do update set display_name = excluded.display_name, updated_at = now();
        return jsonb_build_object('status','saved');
    end if;
    if action = 'settings' then
        prefs := args->'preferences';
        expected := (args->>'expected')::integer;
        select * into settings from survivor_private.player_settings where account_id = player;
        if expected is distinct from coalesce(settings.revision, 0)
        then return jsonb_build_object('status','conflict'); end if;
        if (jsonb_typeof(prefs) = 'object' and jsonb_typeof(prefs->'camera_steering') = 'boolean'
            and jsonb_typeof(prefs->'run') = 'boolean' and prefs->>'sensitivity' in ('0.65','1.0','1.4')) is not true
        then return jsonb_build_object('status','invalid'); end if;
        prefs := jsonb_build_object('camera_steering', prefs->'camera_steering',
            'run', prefs->'run', 'sensitivity', prefs->'sensitivity');
        insert into survivor_private.player_settings(account_id, preferences, revision)
            values (player, prefs, expected + 1) on conflict (account_id) do update
            set preferences = excluded.preferences, revision = excluded.revision, updated_at = now();
        return jsonb_build_object('status','saved','revision',expected + 1);
    end if;

    slot_id := (args->>'id')::uuid;
    select * into selected from survivor_private.save_slots s where s.id = slot_id and s.account_id = player;
    if action = 'get' then
        if selected.id is null or selected.deleted_at is not null then return jsonb_build_object('status','missing'); end if;
        select * into previous from survivor_private.save_revisions r where r.save_id = slot_id
            and r.revision = coalesce((args->>'revision')::integer, selected.current_revision);
        if not found then return jsonb_build_object('status','missing'); end if;
        return jsonb_build_object('status','found','save',survivor_private.save_metadata(selected),
            'snapshot',previous.snapshot,'revision',previous.revision);
    end if;

    expected := (args->>'expected')::integer;
    if action = 'delete' then
        if selected.id is null or selected.deleted_at is not null then return jsonb_build_object('status','deleted'); end if;
        if expected is distinct from selected.current_revision then
            return jsonb_build_object('status','conflict','save',survivor_private.save_metadata(selected));
        end if;
        delete from survivor_private.save_revisions where save_id = slot_id;
        update survivor_private.save_slots set deleted_at = now() where id = slot_id and account_id = player;
        -- Bound metadata tombstones while fencing delayed creates for recent deletions.
        delete from survivor_private.save_slots where id in (
            select s.id from survivor_private.save_slots s where s.account_id = player
                and s.deleted_at is not null order by s.deleted_at desc, s.id offset 128);
        return jsonb_build_object('status','deleted');
    end if;

    if action is distinct from 'put' then return jsonb_build_object('status','invalid'); end if;
    operation := (args->>'operation')::uuid;
    raw := args->>'snapshot';
    if operation is null or slot_id is null or expected is null or expected < 0
    then return jsonb_build_object('status','invalid'); end if;
    envelope := survivor_private.checked_snapshot(raw);
    if envelope is null then return jsonb_build_object('status','invalid_snapshot'); end if;
    state := envelope->'state';
    snapshot_hash := encode(sha256(convert_to(raw, 'UTF8')), 'hex');
    if selected.deleted_at is not null then return jsonb_build_object('status','missing'); end if;
    if selected.id is not null then
        select * into previous from survivor_private.save_revisions r
            where r.save_id = slot_id and r.operation_id = operation;
        if found then
            if previous.checksum <> snapshot_hash or previous.expected_revision <> expected
            then return jsonb_build_object('status','operation_mismatch'); end if;
            return jsonb_build_object('status','saved','revision',previous.revision);
        end if;
        if expected <> selected.current_revision then
            return jsonb_build_object('status','conflict','save',survivor_private.save_metadata(selected));
        end if;
    if selected.id is not null then
        select survivor_private.checked_snapshot(r.snapshot)->'state' into prior_state
            from survivor_private.save_revisions r where r.save_id = slot_id and r.revision = selected.current_revision;
        if state->>'ruleset' = 'configurable-single-player' or prior_state->>'ruleset' = 'configurable-single-player' then
            if prior_state is null or prior_state->'ruleset' is distinct from state->'ruleset'
                or prior_state->'configuration' is distinct from state->'configuration'
                or prior_state->'player_id' is distinct from state->'player_id'
                or prior_state->'seed' is distinct from state->'seed' then
                return jsonb_build_object('status','invalid_snapshot');
            end if;
        end if;
    end if;
        if selected.season_id <> state->>'season_id'
        then return jsonb_build_object('status','invalid_snapshot'); end if;
    else
        if expected <> 0 then return jsonb_build_object('status','missing'); end if;
        if (select count(*) from survivor_private.save_slots s
            where s.account_id = player and s.deleted_at is null) >= 3
        then return jsonb_build_object('status','capacity'); end if;
        if args->'guest_import' = 'true' and exists (select 1 from survivor_private.save_slots s
            where s.account_id = player and s.season_id = state->>'season_id' and s.deleted_at is null)
        then return jsonb_build_object('status','already_imported'); end if;
        insert into survivor_private.save_slots(id, account_id, season_id, current_revision, day, tick)
            values (slot_id, player, state->>'season_id', 1, (state->>'day')::integer, (state->>'tick')::integer)
            on conflict (id) do nothing;
        if not found then return jsonb_build_object('status','missing'); end if;
    end if;
    next_revision := expected + 1;
    insert into survivor_private.save_revisions(save_id, revision, snapshot, schema_version,
        ruleset_version, game_version, checksum, operation_id, expected_revision)
    values (slot_id, next_revision, raw, (envelope->>'schema')::integer,
        (state->>'ruleset_version')::integer, envelope->>'game_version', snapshot_hash, operation, expected);
    update survivor_private.save_slots set current_revision = next_revision,
        day = (state->>'day')::integer, tick = (state->>'tick')::integer, updated_at = now()
        where id = slot_id and account_id = player;
    delete from survivor_private.save_revisions where save_id = slot_id and revision <= next_revision - 3;
    return jsonb_build_object('status','saved','revision',next_revision);
exception when data_exception then
    return jsonb_build_object('status','invalid');
end;
$$;
