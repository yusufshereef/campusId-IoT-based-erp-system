# CampusID attendance demo starter

## Requirements

Install Node.js 20.19+ or 22.12+ and create a Supabase project.

## Database setup

1. Open Supabase Dashboard → SQL Editor → New query.
2. Paste and run [`supabase/schema.sql`](./supabase/schema.sql). This is the
   secure baseline: it creates the tables, enables RLS, removes legacy demo
   policies, grants no anonymous table access, and does not create an
   administrator.
3. Apply
   [`20261010234000_register_teacher_with_classes.sql`](./supabase/migrations/20261010234000_register_teacher_with_classes.sql).
   It creates the transactional teacher-registration RPC without anonymous
   execution.
4. Apply
   [`20261015223000_secure_auth_and_rls.sql`](./supabase/migrations/20261015223000_secure_auth_and_rls.sql).
   It is idempotent and reasserts the secure grants, policies, helper
   functions, and RPC authorization.
5. Apply
   [`20261015233000_least_privilege_table_grants.sql`](./supabase/migrations/20261015233000_least_privilege_table_grants.sql).
   It removes browser table privileges not required by the current UI.
6. In Table Editor, verify `classes`, `people`, `teacher_classes`,
   `fingerprint_mappings`, and `user_roles` exist. Verify that the SQL Editor
   reports no policies for `anon` and no `anon` execute grant on the RPC.
7. Create the first Auth user in Supabase Authentication, then provision it
   manually as an administrator using the SQL shown below. Never grant the
   administrator role to `anon` or to all authenticated users.

## Connect the app

1. In Supabase Project Settings → API, copy the Project URL and publishable key (or legacy anon key). Never use the `service_role`/secret key in a browser.
2. Copy `.env.example` to `.env.local` in the project root. Replace placeholders with your URL and public key.
3. Restart the dev server after editing environment variables.

## Run locally

```bash
npm install
npm run dev
```

Open the localhost address printed in terminal, usually http://localhost:5173.

## Isolated Supabase test environment

Do not use the production/demo URL for integration tests. Create a separate
Supabase project named for testing, then run the complete [`supabase/schema.sql`](./supabase/schema.sql), followed
by every file in [`supabase/migrations/`](./supabase/migrations/) in timestamp
order. The schema creates `classes`, `people`, `teacher_classes`,
`fingerprint_mappings`, `user_roles`, their foreign keys and secure RLS
policies. The first migration creates the protected
`register_teacher_with_classes` RPC; the final migration reasserts the
complete security baseline.

Copy the test project's URL and publishable/anon key to a local, ignored
`.env.local` only. Never put a service-role/secret key in Vite variables or
source control. The repository's `.env.example` contains placeholders only.

Run the repeatable integration verification in the Supabase SQL editor against
the test project:

```sql
\i supabase/test/isolated-admin-workflow.sql
```

If the SQL editor does not support `\i`, paste that file's contents. It starts
a transaction, creates two labelled classes, registers one labelled teacher,
checks the returned teacher and exactly two assignments, checks duplicate and
invalid-class failures, and rolls everything back. It therefore leaves no
test records. For a persistent test run, use only the separate test project
and remove its test rows from the SQL editor with the project owner/admin
connection; never add a DELETE policy to production.

After applying the security migration, run
[`supabase/test/security-rls-workflow.sql`](./supabase/test/security-rls-workflow.sql)
in the disposable project. It verifies anonymous denial, teacher read-only
assignment scope, teacher denial of privileged writes/RPC calls, and
administrator writes, then rolls back all fixtures.

Both SQL tests intentionally require a disposable project and a privileged SQL
Editor session. The teacher-registration RPC does not provide a privileged
owner-session bypass: the tests create temporary Auth users, switch to the
`authenticated` database role, and set transaction-local `request.jwt.claims`
for the administrator/teacher checks. If SQL Editor stops before the final
`rollback`, run `rollback;` in that same session before closing it. Do not
run either test against the configured application project.

### Authentication setup

Create administrator and teacher accounts in Supabase Authentication using the
Dashboard or an approved identity provider. The security migration does not
choose or silently create the first administrator. As the project owner, run
the following one-time SQL after creating an Auth user:

```sql
insert into public.user_roles (user_id, role)
values ('AUTH_USER_UUID', 'administrator');
```

For a teacher, first register the teacher as an administrator, then link the
Auth user to the teacher's `people.id`:

```sql
insert into public.user_roles (user_id, role, person_id)
values ('AUTH_USER_UUID', 'teacher', 'TEACHER_PERSON_UUID');
```

The browser uses only the publishable/anon key and an Auth session. Never put
the `service_role` key in `.env.local`, Vite variables, or frontend code.

## Test

1. Create class CSE, section A, year 2026-27.
2. Create class CSE, section B.
3. Register a student with a unique roll number and assign CSE-A.
4. Register a teacher with a unique employee ID and assign both classes.
5. Refresh; records should remain saved. Duplicate class names/sections, roll
   numbers, and employee IDs are rejected without a success notice.
6. Fingerprint status is read-only in the web app. It does not enroll or simulate a real finger.

## Next milestone: ESP32-WROOM-32 and R307

The next implementation must be a separate hardware integration milestone:

1. Connect the R307 UART TX/RX to the ESP32-WROOM-32 using 3.3 V-safe,
   crossed serial lines and a common ground; confirm the sensor power
   requirements from its board documentation.
2. Implement a small ESP32 firmware state machine for sensor handshake,
   two-image enrollment, template creation, and slot capture. Report success
   only after the R307 acknowledgement packet confirms the slot.
3. Send a signed/authenticated enrollment result containing `device_id`,
   `slot_id`, and a person identifier to a backend endpoint. The browser must
   not directly receive or store fingerprint templates.
4. Persist the mapping only after validating the device, positive slot ID,
   person, and uniqueness; report sensor timeout, duplicate template, and
   unreachable-device errors explicitly.
5. Add mocked serial packet tests first, then perform a physical test with
   documented wiring and a real finger. Attendance remains a later milestone.

## Important security note

The repository now defines a secure-by-default database baseline, but the
deployed project is not considered secure until the migrations have been
applied there and the RLS verification script has passed. The browser uses
only the publishable/anon key; never place a `service_role`/secret key in
Vite variables or frontend code. Fingerprint mappings remain inaccessible to
the browser until a device-authenticated backend exists.

## Current scope

Class creation/listing, student/teacher registration, class assignments, search, activation/deactivation, authenticated sign-in, role-aware access, and live database counts are implemented. The people/classes query uses separate requests to avoid the ambiguous PostgREST relationship between `people.class_id` and `teacher_classes`. Class editing/deletion, real ESP32/R307 enrollment, attendance sessions, attendance marking, and offline sync are not implemented yet.

The dashboard never marks a fingerprint enrolled from a browser click. A future authenticated terminal service must return a verified R307 slot result before updating `people.fingerprint_status` and `fingerprint_mappings`. The deployed database still requires manual migration and RLS verification; do not use it with real student or biometric data until that deployment step is complete.
