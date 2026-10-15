# Isolated Supabase integration test

1. Create a separate Supabase project, or start a local Supabase stack with
   `supabase start` when Docker and the Supabase CLI are installed. Do not
   point this at the demo/production project. A plain PostgreSQL server is not
   sufficient because these tests require Supabase Auth's `auth` schema,
   `auth.uid()`, and the `anon`/`authenticated` roles.
2. Run `../schema.sql`, then apply all timestamped files in
   `../migrations/` in timestamp order:
   `20261010234000_register_teacher_with_classes.sql`, followed by
   `20261015223000_secure_auth_and_rls.sql`, followed by
   `20261015233000_least_privilege_table_grants.sql`.
3. Confirm the five tables, secure policies, helper functions, and the
   administrator-only RPC exist in the test project's SQL editor.
4. Paste and run `isolated-admin-workflow.sql`. It runs the valid two-class
   registration, duplicate employee test, invalid class test, and verification
   query in one transaction, then rolls back.
5. Confirm the verification query returns one teacher with exactly two rows
   before the script's final `rollback`.

Run `security-rls-workflow.sql` after the same setup to verify the hardened
policies. It uses temporary Auth users to check anonymous denial, teacher
read-only access to assigned classes, teacher denial of writes and teacher
registration, administrator write access, and the absence of `CREATE`
privilege on the `public` schema for `anon` and `authenticated`. It also ends
with `rollback`.
The script must be run by a project owner or database role that can create
temporary rows in `auth.users`; never run it against production data.

The RPC requires a real authenticated administrator context; a privileged SQL
editor session without `auth.uid()` is intentionally denied. If SQL Editor
stops after an assertion or other error, run `rollback;` in the same session
before closing it. The denied-read checks accept either zero rows from RLS or
an exact SQLSTATE `42501` privilege denial; unexpected errors are not treated
as successful denials.

The script requires no secret key and does not modify production. The
publishable key may be used only for browser reads/writes in the disposable
test project; never expose a service-role key to Vite.

## Exact execution options

### Supabase CLI local stack

From the repository root, after installing Docker and the Supabase CLI:

```bash
supabase start
DB_URL="$(supabase status -o env | sed -n 's/^DB_URL=//p')"
test -n "$DB_URL"
psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/schema.sql
psql "$DB_URL" -v ON_ERROR_STOP=1 \
  -f supabase/migrations/20261010234000_register_teacher_with_classes.sql
psql "$DB_URL" -v ON_ERROR_STOP=1 \
  -f supabase/migrations/20261015223000_secure_auth_and_rls.sql
psql "$DB_URL" -v ON_ERROR_STOP=1 \
  -f supabase/migrations/20261015233000_least_privilege_table_grants.sql
psql "$DB_URL" \
  -v ON_ERROR_STOP=1 -f supabase/test/isolated-admin-workflow.sql
psql "$DB_URL" \
  -v ON_ERROR_STOP=1 -f supabase/test/security-rls-workflow.sql
supabase stop
```

`DB_URL` is obtained only from the disposable local Supabase CLI status
output. Do not source `.env.local`, read its contents, or substitute the
configured hosted project's URL or credentials.

The repository SQL files are not currently wired into a Supabase CLI
`supabase/migrations` directory, so `supabase db reset` alone does not apply
this repository's baseline. The explicit `psql` commands above apply the
baseline and all three timestamped migrations before running the tests.

Each setup command uses `-v ON_ERROR_STOP=1`; if one fails, do not continue to
the next command. Fix the setup issue and rerun the setup from a clean
disposable database, preferably after `supabase db reset`. If a test fails,
the `psql` connection closes and PostgreSQL rolls back its open transaction.
When using SQL Editor or another persistent session, run `ROLLBACK;` in that
same session before retrying. Never leave a failed test transaction open.

### Disposable hosted Supabase project

1. Create a separate test project in the Supabase dashboard.
2. In SQL Editor, run the complete contents of `supabase/schema.sql`.
3. Run `supabase/migrations/20261010234000_register_teacher_with_classes.sql`.
4. Run `supabase/migrations/20261015223000_secure_auth_and_rls.sql`.
5. Run `supabase/migrations/20261015233000_least_privilege_table_grants.sql`.
6. In the same SQL Editor session, paste and run
   `supabase/test/isolated-admin-workflow.sql`.
7. In a new SQL Editor query, paste and run
   `supabase/test/security-rls-workflow.sql`.
8. Run the catalog verification query below.

Do not use the configured application project, real records, real Auth users,
or biometric data. If a script errors before its final `rollback`, execute
`rollback;` in that same SQL Editor session. Do not rerun a failed transaction
until the rollback has completed.

## Effective-state verification query

Run this only in the disposable project after both tests:

```sql
select grantee, table_schema, table_name, privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name in (
    'classes', 'people', 'teacher_classes',
    'fingerprint_mappings', 'user_roles'
  )
order by grantee, table_name, privilege_type;

select grantee, routine_schema, routine_name, privilege_type
from information_schema.routine_privileges
where routine_schema = 'public'
  and routine_name in (
    'current_user_role',
    'is_administrator',
    'is_teacher_for_class',
    'register_teacher_with_classes'
  )
order by grantee, routine_name, privilege_type;

select schemaname, tablename, policyname, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
order by tablename, policyname;

select n.nspname as schema_name,
       p.proname,
       pg_get_userbyid(p.proowner) as owner,
       p.prosecdef as security_definer,
       coalesce(array_to_string(p.proconfig, ', '), '') as configuration
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'current_user_role',
    'is_administrator',
    'is_teacher_for_class',
    'register_teacher_with_classes'
  )
order by p.proname;

with schema_acl as (
  select acl.grantee,
         acl.privilege_type,
         acl.is_grantable
  from pg_namespace n
  cross join lateral aclexplode(
    coalesce(n.nspacl, acldefault('n', n.nspowner))
  ) as acl
  where n.nspname = 'public'
),
principals(principal_name) as (
  values
    ('PUBLIC'::name),
    ('anon'::name),
    ('authenticated'::name),
    ('service_role'::name)
),
privileges(privilege_type) as (
  values
    ('USAGE'::text),
    ('CREATE'::text)
)
select p.principal_name,
       v.privilege_type,
       case
         when p.principal_name = 'PUBLIC' then exists (
           select 1
           from schema_acl a
           where a.grantee = 0
             and a.privilege_type = v.privilege_type
         )
         else has_schema_privilege(
           p.principal_name,
           'public',
           v.privilege_type
         )
       end as effective_privilege,
       exists (
         select 1
         from schema_acl a
         left join pg_roles r on r.oid = a.grantee
         where a.privilege_type = v.privilege_type
           and (
             (p.principal_name = 'PUBLIC' and a.grantee = 0)
             or r.rolname = p.principal_name
           )
       ) as direct_acl_entry,
       (
         select a.is_grantable
         from schema_acl a
         left join pg_roles r on r.oid = a.grantee
         where a.privilege_type = v.privilege_type
           and (
             (p.principal_name = 'PUBLIC' and a.grantee = 0)
             or r.rolname = p.principal_name
           )
         limit 1
       ) as is_grantable
from principals p
cross join privileges v
order by p.principal_name, v.privilege_type;
```

Expected evidence includes no `anon` table grants or RPC execute grants,
authenticated execute only for the four intended functions, administrator-only
write policies, teacher class scoping, `using (false)` for browser fingerprint
mapping access, `SECURITY DEFINER` functions owned by a trusted database role,
and `search_path=pg_catalog, public`. For the `public` schema privilege query,
`PUBLIC` should retain `USAGE` but not `CREATE` after the migrations. The
`anon`, `authenticated`, and `service_role` rows report effective privileges,
including privileges inherited from `PUBLIC`; `direct_acl_entry` distinguishes
an explicit role grant from inherited access. `CREATE` should be false for all
four principals, while `USAGE` may be true through the default/public schema
ACL.
