-- Run with psql -v ON_ERROR_STOP=1 after a local reset. No persisted test data.
begin;
do $$
declare table_name text;
begin
    foreach table_name in array array['profiles','player_settings','save_slots','save_revisions'] loop
        if not exists (
            select from pg_class c join pg_namespace n on c.relnamespace = n.oid
            where n.nspname = 'survivor_private' and c.relname = table_name and c.relrowsecurity
        ) then raise exception 'Missing RLS on %', table_name; end if;
        if has_table_privilege('anon', 'survivor_private.' || table_name, 'select')
            or has_table_privilege('authenticated', 'survivor_private.' || table_name,
                'select,insert,update,delete')
        then raise exception 'Direct table grant on %', table_name; end if;
    end loop;
    if has_function_privilege('anon', 'public.player_data(text,jsonb)', 'execute')
        or not has_function_privilege('authenticated', 'public.player_data(text,jsonb)', 'execute')
        or has_function_privilege('authenticated', 'survivor_private.checked_snapshot(text)', 'execute')
    then raise exception 'Unexpected function grants'; end if;
    if (select prosecdef from pg_proc where oid = 'public.player_data(text,jsonb)'::regprocedure)
        or not (select prosecdef from pg_proc where oid = 'survivor_private.player_data(text,jsonb)'::regprocedure)
    then raise exception 'Unexpected function privilege mode'; end if;
end
$$;
set local role authenticated;
do $$
begin
    perform public.player_data('list');
    raise exception 'A role with no verified session could read player data';
exception when insufficient_privilege then
    null;
end
$$;
rollback;
