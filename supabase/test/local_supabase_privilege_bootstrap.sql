-- LOCAL DEVELOPMENT ONLY — do not run against Digi_SEO_Test or production.
--
-- Restores the standard Supabase-platform base-table/sequence privilege
-- bootstrap (GRANT SELECT/INSERT/UPDATE/DELETE on every public-schema table,
-- USAGE/SELECT on every sequence, to `anon`/`authenticated`, plus the
-- matching `ALTER DEFAULT PRIVILEGES` so future tables inherit it) that a
-- hosted Supabase project provisions automatically once, outside of any
-- migration file, and that a real project never loses because it is never
-- schema-dropped. The local Supabase CLI's `supabase db reset` runs
-- `DROP SCHEMA public CASCADE; CREATE SCHEMA public;` before replaying
-- migrations, which also destroys this bootstrap — so every `db reset`
-- on a fresh local stack needs it reapplied. No repository migration
-- performs this (repo convention only ever grants `EXECUTE` on individual
-- RPCs, plus two narrow `GRANT SELECT ... TO authenticated` on specific
-- views — see `SEO_RECOMMENDATION_GENERATION_STAGE2_VERIFICATION.md`),
-- matching how the equivalent hosted-platform bootstrap is also never a
-- migration on `Digi_SEO_Test` or production.
--
-- This script is idempotent (every statement is safe to re-run), grants
-- nothing beyond the standard `anon`/`authenticated` table-DML convention,
-- and never touches Row Level Security — RLS remains the actual
-- authorization boundary; this script only restores the ability for
-- PostgREST to reach RLS evaluation at all. Never run this against a
-- `--linked` project; it is meaningful only for a fresh local reset.
--
-- Usage (local only):
--   docker exec -i <local-db-container> psql -U postgres -d postgres \
--     < supabase/test/local_supabase_privilege_bootstrap.sql
-- or, if `supabase/config.toml` is present and targets the local stack:
--   supabase db execute -f supabase/test/local_supabase_privilege_bootstrap.sql --local

begin;

grant usage on schema public to anon, authenticated;

grant select, insert, update, delete on all tables in schema public to anon, authenticated;
grant usage, select on all sequences in schema public to anon, authenticated;

alter default privileges for role postgres in schema public
  grant select, insert, update, delete on tables to anon, authenticated;
alter default privileges for role postgres in schema public
  grant usage, select on sequences to anon, authenticated;

commit;

-- Verification section (read-only; safe to run standalone).
do $$
declare
  v_missing_grants integer;
  v_tables_without_rls integer;
  v_total_tables integer;
begin
  select count(*) into v_missing_grants
  from pg_tables t
  where t.schemaname = 'public'
    and not exists (
      select 1 from information_schema.role_table_grants g
      where g.table_schema = 'public'
        and g.table_name = t.tablename
        and g.grantee = 'authenticated'
        and g.privilege_type = 'SELECT'
    );

  select count(*) into v_tables_without_rls
  from pg_tables t
  join pg_class c
    on c.relname = t.tablename
   and c.relnamespace = (select oid from pg_namespace where nspname = 'public')
  where t.schemaname = 'public'
    and c.relrowsecurity = false;

  select count(*) into v_total_tables from pg_tables where schemaname = 'public';

  raise notice 'local_supabase_privilege_bootstrap: % public tables total', v_total_tables;
  raise notice 'local_supabase_privilege_bootstrap: % tables still missing authenticated SELECT (expect 0)', v_missing_grants;
  raise notice 'local_supabase_privilege_bootstrap: % tables without RLS enabled (expect 0 — must remain unchanged by this script)', v_tables_without_rls;

  if v_missing_grants > 0 then
    raise exception 'local_supabase_privilege_bootstrap: FAILED — % table(s) still missing the authenticated SELECT grant', v_missing_grants;
  end if;

  if v_tables_without_rls > 0 then
    raise exception 'local_supabase_privilege_bootstrap: FAILED — % table(s) have RLS disabled; this script must never cause that', v_tables_without_rls;
  end if;

  raise notice 'local_supabase_privilege_bootstrap: ALL CHECKS PASSED — base grants restored, RLS unchanged';
end $$;
