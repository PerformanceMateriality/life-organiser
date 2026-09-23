-- Ground truth for the schema, straight from the database.
--
-- Why: gym-setup.sql, gym-v2-setup.sql and tasks-setup.sql were delivered as chat
-- attachments in Cowork and run by hand, so they are not in version control and the
-- schema can't be reconstructed from it. This reads the live database instead of
-- guessing, so the setup files we commit match what is actually there.
--
-- How: paste the whole query into the Supabase SQL Editor, run it, then copy the
-- result back. It is read-only — it touches nothing.

with t as (
  select c.oid, c.relname, c.relrowsecurity
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r'
)
select tbl, part, detail
from (
  -- columns, in ordinal position
  select t.relname::text as tbl, 1 as sect, a.attnum::int as ord, 'column'::text as part,
         (a.attname || ' :: ' || format_type(a.atttypid, a.atttypmod)
           || case when a.attnotnull then ' NOT NULL' else '' end
           || coalesce(' DEFAULT ' || pg_get_expr(d.adbin, d.adrelid), ''))::text as detail
  from t
  join pg_attribute a on a.attrelid = t.oid and a.attnum > 0 and not a.attisdropped
  left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum

  -- primary keys, foreign keys, uniques, checks — verbatim definitions
  union all
  select t.relname::text, 2, 0, 'constraint'::text,
         (con.conname || ' :: ' || pg_get_constraintdef(con.oid))::text
  from t join pg_constraint con on con.conrelid = t.oid

  union all
  select t.relname::text, 3, 0, 'index'::text,
         (i.indexname || ' :: ' || i.indexdef)::text
  from t join pg_indexes i on i.schemaname = 'public' and i.tablename = t.relname

  union all
  select t.relname::text, 4, 0, 'rls'::text,
         (case when t.relrowsecurity then 'ENABLED' else 'DISABLED' end)::text
  from t

  union all
  select p.tablename::text, 5, 0, 'policy'::text,
         (p.policyname || ' :: ' || p.cmd || ' TO ' || array_to_string(p.roles, ',')
           || ' USING (' || coalesce(p.qual, '-') || ')'
           || ' WITH CHECK (' || coalesce(p.with_check, '-') || ')')::text
  from pg_policies p where p.schemaname = 'public'

  union all
  select g.table_name::text, 6, 0, 'grant'::text,
         (g.grantee || ' :: ' || g.privilege_type)::text
  from information_schema.role_table_grants g
  where g.table_schema = 'public'

  union all
  select t.relname::text, 7, 0, 'trigger'::text,
         (tg.tgname || ' :: ' || pg_get_triggerdef(tg.oid))::text
  from t join pg_trigger tg on tg.tgrelid = t.oid and not tg.tgisinternal
) x
order by tbl, sect, ord, detail;
