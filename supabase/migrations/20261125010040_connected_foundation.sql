-- Only the RPC facade is exposed by PostgREST. App tables have no client grants.
create schema survivor_private;
revoke all on schema survivor_private from public, anon, authenticated;
grant usage on schema survivor_private to authenticated;

create table survivor_private.profiles (
    account_id uuid primary key references auth.users(id) on delete cascade,
    display_name text not null default 'Explorer' check (char_length(display_name) between 1 and 40),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table survivor_private.player_settings (
    account_id uuid primary key references auth.users(id) on delete cascade,
    preferences jsonb not null,
    revision integer not null check (revision > 0),
    updated_at timestamptz not null default now()
);

create table survivor_private.save_slots (
    id uuid primary key,
    account_id uuid not null references auth.users(id) on delete cascade,
    season_id text not null check (season_id ~ '^[0-9a-f]{32}$'),
    mode text not null default 'private_single_player' check (mode = 'private_single_player'),
    current_revision integer not null check (current_revision > 0),
    day integer not null check (day > 0),
    tick integer not null check (tick >= 0),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz
);
create index save_slots_account_idx on survivor_private.save_slots (account_id, updated_at desc);

create table survivor_private.save_revisions (
    save_id uuid not null references survivor_private.save_slots(id) on delete cascade,
    revision integer not null check (revision > 0),
    snapshot text not null check (octet_length(snapshot) <= 256000),
    schema_version integer not null check (schema_version between 1 and 2),
    ruleset_version integer not null check (ruleset_version = 1),
    game_version text not null check (char_length(game_version) between 1 and 24),
    checksum text not null check (checksum ~ '^[0-9a-f]{64}$'),
    operation_id uuid not null,
    expected_revision integer not null check (expected_revision = revision - 1),
    created_at timestamptz not null default now(),
    primary key (save_id, revision),
    unique (save_id, operation_id)
);

alter table survivor_private.profiles enable row level security;
alter table survivor_private.player_settings enable row level security;
alter table survivor_private.save_slots enable row level security;
alter table survivor_private.save_revisions enable row level security;
revoke all on all tables in schema survivor_private from public, anon, authenticated;

create function survivor_private.save_metadata(s survivor_private.save_slots) returns jsonb
language sql immutable set search_path = '' as $$
    select jsonb_build_object('id', s.id, 'season_id', s.season_id, 'mode', s.mode,
        'revision', s.current_revision, 'day', s.day, 'tick', s.tick,
        'created_at', s.created_at, 'updated_at', s.updated_at);
$$;

-- Validate the wire envelope, checksum, version and simulation structure on the server.
-- The game additionally applies SaveCodec's full rules before saving and restoring.
create function survivor_private.checked_snapshot(raw text) returns jsonb
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
begin
    if raw is null or octet_length(raw) > 256000 then return null; end if;
    wrapper := raw::jsonb;
    if (jsonb_typeof(wrapper->'payload') = 'string'
        and wrapper->>'sha256' = encode(sha256(convert_to(wrapper->>'payload', 'UTF8')), 'hex')) is not true
    then return null; end if;
    envelope := (wrapper->>'payload')::jsonb;
    state := envelope->'state';
    tick := (state->>'tick')::integer;
    if ((envelope->>'schema')::integer between 1 and 2
        and envelope->>'game_version' ~ '^[0-9]+[.][0-9]+[.][0-9]+$'
        and char_length(envelope->>'game_version') <= 24
        and (envelope->>'timestamp')::bigint between 1 and 4102444800
        and (envelope->>'save_revision')::bigint between 1 and 4000000000
        and state->>'season_id' ~ '^[0-9a-f]{32}$'
        and state->>'player_id' ~ '^[0-9a-f]{32}$'
        and jsonb_typeof(state->'seed') = 'string'
        and (state->>'seed')::bigint::text = state->>'seed'
        and jsonb_typeof(state->'rng_state') = 'string'
        and (state->>'rng_state')::bigint::text = state->>'rng_state'
        and state->>'ruleset' = 'technical-season'
        and state->'ruleset_version' = '1'::jsonb
        and state->>'phase' = 'camp' and state->>'controlled' = 'explorer'
        and (state->>'revision')::bigint between tick and 4000000000
        and tick between 0 and 1000000000 and (state->>'day')::integer = tick / 2400 + 1
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
            and (jsonb_typeof(pose->'underwater') = 'boolean' or (envelope->>'schema')::int = 1)) is not true
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
           and (camp->>'arrivals')::bigint between 0 and 4000000000) is not true
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
                and (person->>'deadline')::bigint between 0 and tick + 112
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
                    and (receipt->>'tick')::integer between 0 and tick
                    and receipt->>'with' <> id and camp->'people' ? (receipt->>'with')
                    and receipt->>'topic' in ('camp','water')
                    and jsonb_typeof(receipt->'reply') = 'string' and char_length(receipt->>'reply') <= 512
                    and not (receipt->>'id' = any(receipts))) is not true then return null; end if;
                receipts := array_append(receipts, receipt->>'id');
            end loop;
        end loop;
    end loop;
    return envelope;
exception when data_exception then
    return null;
end;
$$;

create function survivor_private.player_data(action text, args jsonb) returns jsonb
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

revoke all on all functions in schema survivor_private from public, anon, authenticated;
grant execute on function survivor_private.player_data(text, jsonb) to authenticated;

create function public.player_data(action text, args jsonb default '{}'::jsonb) returns jsonb
language sql security invoker set search_path = '' as $$
    select survivor_private.player_data(action, args);
$$;

revoke all on function public.player_data(text,jsonb) from public, anon, authenticated;
grant execute on function public.player_data(text,jsonb) to authenticated;
