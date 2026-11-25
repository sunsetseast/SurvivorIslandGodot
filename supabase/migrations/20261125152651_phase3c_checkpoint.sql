-- One server-owned recovery row for the dedicated test deployment.
create schema survivor_multiplayer;
revoke all on schema survivor_multiplayer from public, anon, authenticated, service_role;
grant usage on schema survivor_multiplayer to anon;

create table survivor_multiplayer.recovery (
    singleton boolean primary key default true check (singleton),
    revision bigint not null default 0 check (revision >= 0),
    payload jsonb,
    updated_at timestamptz not null default now(),
    secret_hash bytea not null check (octet_length(secret_hash) = 32),
    check (payload is null or (jsonb_typeof(payload) = 'object' and octet_length(payload::text) <= 1100000))
);
alter table survivor_multiplayer.recovery enable row level security;
revoke all on survivor_multiplayer.recovery from public, anon, authenticated, service_role;

-- A separate random 256-bit credential scopes this operation to the single row.
-- Anonymous calls supply no user JWT. No table or Auth admin privileges are granted.
create function survivor_multiplayer.checkpoint(secret text, expected bigint, payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
    row_value survivor_multiplayer.recovery;
begin
    if secret is null or length(secret) <> 64 or secret !~ '^[0-9a-f]{64}$' then
        raise insufficient_privilege using message = 'server_required';
    end if;
    select * into row_value from survivor_multiplayer.recovery r
        where r.singleton and r.secret_hash = pg_catalog.sha256(pg_catalog.convert_to(secret, 'UTF8'));
    if not found then
        raise insufficient_privilege using message = 'server_required';
    end if;
    if expected = -1 and payload is null then
        return jsonb_build_object('revision', row_value.revision, 'state', row_value.payload);
    end if;
    if expected is null or expected < 0 or payload is null or jsonb_typeof(payload) <> 'object'
        or octet_length(payload::text) > 1100000 then
        raise invalid_parameter_value using message = 'invalid_checkpoint';
    end if;
    update survivor_multiplayer.recovery r
        set revision = r.revision + 1, payload = checkpoint.payload, updated_at = now()
        where r.singleton and r.revision = expected and r.secret_hash = row_value.secret_hash
        returning * into row_value;
    if not found then
        raise serialization_failure using message = 'checkpoint_conflict';
    end if;
    return jsonb_build_object('revision', row_value.revision);
end;
$$;

create function public.phase3c_checkpoint(secret text, expected bigint, payload jsonb)
returns jsonb language sql security invoker set search_path = '' as $$
    select survivor_multiplayer.checkpoint(secret, expected, payload);
$$;

revoke all on function survivor_multiplayer.checkpoint(text,bigint,jsonb) from public, anon, authenticated, service_role;
revoke all on function public.phase3c_checkpoint(text,bigint,jsonb) from public, anon, authenticated, service_role;
grant execute on function survivor_multiplayer.checkpoint(text,bigint,jsonb) to anon;
grant execute on function public.phase3c_checkpoint(text,bigint,jsonb) to anon;
