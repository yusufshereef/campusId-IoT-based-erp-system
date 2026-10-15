# CampusID attendance demo starter

## Requirements

Install Node.js 20.19+ or 22.12+ and create a Supabase project.

## Database setup

1. Open Supabase Dashboard → SQL Editor → New query.
2. Paste all of `supabase/schema.sql` and click Run.
3. In Table Editor, verify `classes`, `people`, `teacher_classes`, and `fingerprint_mappings` exist.
4. Apply the migration in `supabase/migrations/` (or rerun the complete
   `supabase/schema.sql`) before registering teachers. It creates the
   `register_teacher_with_classes` RPC so a teacher and all of its class
   assignments are committed atomically.

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
Supabase project named for testing, then run the complete
[`supabase/schema.sql`](./supabase/schema.sql) followed by every file in
[`supabase/migrations/`](./supabase/migrations/) in timestamp order. The
schema creates `classes`, `people`, `teacher_classes`,
`fingerprint_mappings`, their foreign keys/RLS policies, and the
`register_teacher_with_classes` RPC.

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

The SQL file enables intentionally open policies to make this quick demo easy to test. Anyone who obtains the public project URL/key can read/write the demo tables. Use fake records only. Before real use, implement Supabase Auth and restrictive admin-only Row Level Security policies.

## Current scope

Class creation/listing, student/teacher registration, class assignments, search, activation/deactivation, and live database counts are implemented. The people/classes query uses separate requests to avoid the ambiguous PostgREST relationship between `people.class_id` and `teacher_classes`. Class editing/deletion, admin login, real ESP32/R307 enrollment, attendance sessions, attendance marking, and offline sync are not implemented yet.

The dashboard never marks a fingerprint enrolled from a browser click. A future authenticated terminal service must return a verified R307 slot result before updating `people.fingerprint_status` and `fingerprint_mappings`. The current SQL policies are intentionally open for a fake-data prototype; do not use them with real student or biometric data.
