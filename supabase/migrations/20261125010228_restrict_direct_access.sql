-- Keep direct access denied even if a role later receives a table grant.
create policy rpc_only on survivor_private.profiles as restrictive
    for all to anon, authenticated using (false) with check (false);
create policy rpc_only on survivor_private.player_settings as restrictive
    for all to anon, authenticated using (false) with check (false);
create policy rpc_only on survivor_private.save_slots as restrictive
    for all to anon, authenticated using (false) with check (false);
create policy rpc_only on survivor_private.save_revisions as restrictive
    for all to anon, authenticated using (false) with check (false);

-- New hosted projects may include this automatic RLS event trigger. Remove
-- client EXECUTE while preserving the trigger and its administrative owner.
do $$
begin
    if to_regprocedure('public.rls_auto_enable()') is not null then
        revoke execute on function public.rls_auto_enable() from public, anon, authenticated;
    end if;
end;
$$;
