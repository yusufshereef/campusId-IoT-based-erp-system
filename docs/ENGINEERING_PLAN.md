# CampusID Engineering Plan

## Product direction

CampusID is a college attendance ERP with a React/Vite browser application,
Supabase/PostgreSQL authorization, and a future ESP32/R307S terminal. Database
authorization and data integrity take priority over feature breadth.

## Current baseline

- The browser has Supabase Auth sign-in and role lookup.
- The local SQL baseline is secure by default and grants no anonymous table or
  RPC access.
- `administrator` and assignment-scoped `teacher` roles are stored in
  `public.user_roles`.
- The teacher-registration RPC requires an authenticated administrator.
- Browser access to fingerprint mappings is blocked.
- Classes, students, teachers, assignments, activation, and search are
  implemented.
- Attendance and hardware enrollment are not implemented.

## Security foundation status

### Completed locally

- Removed permissive demo policies from `supabase/schema.sql`.
- Added secure RLS, grants, helper functions, and role storage to the baseline.
- Protected both definitions of `register_teacher_with_classes`.
- Removed the owner-session bypass from the application RPC.
- Updated disposable SQL tests to use simulated Auth users and JWT claims.
- Replaced denied-SELECT exception assumptions with row-count assertions.
- Limited expected denied write/RPC handlers to SQLSTATE `42501`.
- Documented transaction recovery with `ROLLBACK`.
- Hardened all `SECURITY DEFINER` functions with `pg_catalog, public`
  search paths and explicitly revoked `CREATE` on the `public` schema.
- Added explicit `CREATE` privilege assertions for `anon` and
  `authenticated` to the disposable security workflow.
- Applied the security and least-privilege migrations to the disposable local
  Supabase stack and completed both SQL workflows with final `ROLLBACK`.

### Not verified

- No remote migration has been applied.
- Deployed/hosted database state remains unverified.
- The local review confirmed the prior `public`-only search path was dependent
  on deployment schema privileges; the baseline and hardening migration now
  explicitly close that gap.
- Disposable catalog verification confirms the intended authenticated table
  grants, RPC execute privileges, trusted `SECURITY DEFINER` ownership and
  `search_path`, and no `CREATE` privilege for `PUBLIC`, `anon`,
  `authenticated`, or `service_role` on `public`.

### Latest local verification

- `npm test`: passed, 11 tests in 1 file.
- `npm run build`: passed.
- `npx tsc -b --pretty false`: passed.
- `git diff --check`: passed.
- `isolated-admin-workflow.sql`: passed with exit code 0 and final
  `ROLLBACK`.
- `security-rls-workflow.sql`: passed with exit code 0 and final `ROLLBACK`,
  including the `anon` and `authenticated` schema `CREATE` assertions.
- Updated security and least-privilege migrations: applied to the disposable
  local Supabase stack with `psql -v ON_ERROR_STOP=1`.

## Reviewed migration order

1. `supabase/schema.sql`
2. `supabase/migrations/20261010234000_register_teacher_with_classes.sql`
3. `supabase/migrations/20261015223000_secure_auth_and_rls.sql`
4. `supabase/migrations/20261015233000_least_privilege_table_grants.sql`
5. Provision the first administrator manually in `user_roles`.
6. Run the disposable workflow and security SQL tests.

## Next security-verification procedure

The safest supported target is a newly created Supabase test project, or a
local Supabase CLI stack started with Docker. Never use the configured
application project. Apply the baseline and all migrations in the order above,
then run `supabase/test/isolated-admin-workflow.sql` followed by
`supabase/test/security-rls-workflow.sql`. If either transaction stops before
its final `ROLLBACK`, execute `ROLLBACK;` in that same session before retrying.

For the local CLI stack, obtain the connection URL only from
`supabase status -o env` and apply the repository SQL explicitly:

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
psql "$DB_URL" -v ON_ERROR_STOP=1 \
  -f supabase/test/isolated-admin-workflow.sql
psql "$DB_URL" -v ON_ERROR_STOP=1 \
  -f supabase/test/security-rls-workflow.sql
```

Do not read `.env.local` or use credentials from the existing hosted project.
Because these files are not in the CLI-standard `supabase/migrations`
directory, `supabase db reset` alone does not apply them. If setup fails,
stop at the failed command, reset the disposable local database, and rerun
the setup sequence from the beginning. If a test fails in a persistent SQL
session, execute `ROLLBACK;` in that same session before retrying; a closed
`psql` connection rolls back its open transaction automatically.

After both tests, run the catalog queries in `supabase/test/README.md` to
capture effective table grants, routine execute privileges, policies, schema
privileges, function owners, `SECURITY DEFINER` flags, and `search_path`
configuration.

Evidence still required:

- `SET ROLE anon` and `SET ROLE authenticated` in the target Supabase
  environment.
- `auth.uid()` resolving each simulated JWT subject.
- Direct fixture inserts into `auth.users`.
- Complete transaction rollback after every test.
- Effective deployed grants, policy rows, function ownership, and function
  configuration.

## Next approved work

Before dependent ERP or IoT features:

1. Run both SQL tests in a disposable Supabase project.
2. Query effective grants, policies, function ownership, and function
   configuration.
3. Resolve any deployment-specific Auth or SQL Editor behavior.
4. Only then plan attendance schema or device/backend authentication.

## Explicit non-goals for the current security task

- Do not apply migrations to the configured/production Supabase project.
- Do not add attendance features.
- Do not add hardware enrollment.
- Do not expose biometric templates or fingerprint mappings to the browser.
- Do not grant administrator access through frontend state or client claims.
