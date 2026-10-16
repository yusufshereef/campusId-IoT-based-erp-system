# CampusID · Connected campus

An expo-focused IoT attendance prototype: a React + TypeScript workspace, Supabase authentication and PostgreSQL authorization, and an ESP32/R307S fingerprint terminal.

**Working in source:** administrator and teacher sign-in, class/student/teacher registration, assignments, activation, search, and manual attendance with corrections. Firmware performs **local recognition only**. Remote enrollment, device-to-cloud attendance, and durable offline synchronization are not connected yet.

- [Implementation and design](docs/IMPLEMENTATION.md)
- [Hardware feasibility and expo roadmap](docs/EXPO_ROADMAP.md)
- [Firmware setup and existing wiring](firmware/campusid-terminal/README.md)
- [Disposable database tests](supabase/test/README.md)
- [Earlier engineering/security history](docs/ENGINEERING_PLAN.md)

## 1. Prerequisites

- Git.
- Node.js **22.12+ in the 22.x line, 24.x, or 26+**, and npm. Node 20 is no longer supported by the installed Vitest/Supabase versions. `.nvmrc` selects the current Node 22 release.
- A Supabase development project. Use a separate disposable project for SQL tests.
- For firmware: Arduino IDE, Espressif ESP32 board support, and the three Adafruit libraries listed below.

On macOS, if Git reports an invalid developer path, install/repair the Apple command-line tools with `xcode-select --install`. Restart the terminal, then check `git --version`, `node --version`, and `npm --version`.

## 2. Clone and install

```bash
git clone https://github.com/yusufshereef/campusId-IoT-based-erp-system.git
cd campusId-IoT-based-erp-system
# Optional, if nvm is installed:
nvm install
nvm use
npm ci
cp .env.example .env.local
```

PowerShell users can replace the last command with `Copy-Item .env.example .env.local` and install a supported Node version directly if they do not use nvm. Use `npm ci` for a reproducible install from the committed lockfile.

Edit `.env.local`:

```dotenv
VITE_SUPABASE_URL=https://YOUR_PROJECT.supabase.co
VITE_SUPABASE_ANON_KEY=YOUR_PUBLISHABLE_OR_LEGACY_ANON_KEY
```

Find both values under Supabase Project Settings → API. The variable retains its legacy `ANON_KEY` name but accepts a publishable key. Vite embeds these values in the browser bundle: **never use a service-role or secret key**. Keep `.env.local` untracked; restart Vite after editing it. Missing or malformed project URLs show a setup screen instead of crashing startup.

## 3. Initialize a new development database

In the **development project's** Supabase SQL Editor, paste and run each file separately, in this order. Stop on any error:

1. [`supabase/schema.sql`](supabase/schema.sql)
2. [`20261010234000_register_teacher_with_classes.sql`](supabase/migrations/20261010234000_register_teacher_with_classes.sql)
3. [`20261015223000_secure_auth_and_rls.sql`](supabase/migrations/20261015223000_secure_auth_and_rls.sql)
4. [`20261015233000_least_privilege_table_grants.sql`](supabase/migrations/20261015233000_least_privilege_table_grants.sql)
5. [`20261016001000_attendance_records.sql`](supabase/migrations/20261016001000_attendance_records.sql)

The standalone baseline creates the original tables; the timestamped migrations extend/harden them. Running migrations alone on an empty database is insufficient. For an existing project, inspect its applied schema before changing it. This review does not apply hosted migrations.

Verify these tables exist: `classes`, `people`, `teacher_classes`, `fingerprint_mappings`, `user_roles`, `attendance_records`, and `attendance_record_audit`. RLS must remain enabled; anonymous clients have no table access. The teacher-registration RPC is administrator-only. Fingerprint mappings are inaccessible to the browser.

### Provision the first administrator

1. Open Authentication → Users → Add user and create your administrator email/password account. Confirm the account using the dashboard option or email flow.
2. Copy its Auth user UUID.
3. As the project owner in SQL Editor, replace the placeholder and run:

```sql
insert into public.user_roles (user_id, role)
values ('AUTH_USER_UUID', 'administrator');
```

There is no public sign-up or automatic admin creation. A signed-in user without a role sees an account provisioning message.

### Provision a teacher

1. Sign in as the administrator, create a class, and register a teacher with assigned classes.
2. Create that teacher's Auth account in the dashboard.
3. Find the teacher's full `people.id` UUID in Table Editor, then link it:

```sql
insert into public.user_roles (user_id, role, person_id)
values ('TEACHER_AUTH_UUID', 'teacher', 'TEACHER_PERSON_UUID');
```

Registering a teacher in the ERP creates a person and assignments; it does not create an Auth login. Never put administrator credentials in firmware.

## 4. Start development

```bash
npm run dev
```

Open the URL printed by Vite, usually `http://localhost:5173`. Sign in with the provisioned account. Then:

1. Create a class and section.
2. Register students with unique roll numbers and assign the class.
3. Register a teacher and assign classes; provision their Auth account as above.
4. Open Attendance, choose a class and date, and start the session.
5. Mark present, late, excused, or absent. Use the unmarked filter to finish the roster.
6. Reopen the same class/date to inspect saved records. Refresh the roster to see changes from another browser.

Attendance dates use the browser's local calendar. Sessions are in-memory workspace views, not persistent lesson entities. There is one record per student/class/day. Navigating between sections keeps the session; reloading or signing out closes it. Confirmed database records persist. A timeout is reported as unconfirmed until the server state can be read.

## 5. Checks and production preview

```bash
npm run check
npm run preview
```

`check` runs TypeScript, unit tests, formatting verification, and the production build. Preview serves the generated `dist` output; it is not a production backend. For hosting, build with the target project's public environment values and deploy `dist` to a static host over HTTPS.

| Command | Purpose |
| --- | --- |
| `npm run dev` | Vite development server |
| `npm test` | Validation, configuration, and attendance service tests |
| `npm run typecheck` | TypeScript project checks |
| `npm run format` | Format frontend source, package metadata, and HTML |
| `npm run format:check` | Check formatting without modifying files |
| `npm run build` | Typecheck and create production assets |
| `npm run preview` | Inspect the built app locally |

### Database verification

Create a **disposable** Supabase project and apply the same baseline and migration sequence. Paste each test into its SQL Editor:

1. [`isolated-admin-workflow.sql`](supabase/test/isolated-admin-workflow.sql)
2. [`security-rls-workflow.sql`](supabase/test/security-rls-workflow.sql)
3. [`attendance-workflow.sql`](supabase/test/attendance-workflow.sql)

The scripts create temporary Auth/database fixtures inside transactions and end in `ROLLBACK`. If an editor session stops mid-test, run `ROLLBACK;` in that session. SQL Editor does not support psql's `\i` file command; paste the actual contents. See the test README for privileged-session requirements and catalog checks. Unit tests and browser mocks do not establish that your hosted RLS policies are deployed correctly.

## 6. Firmware development

1. Install Arduino IDE and Espressif's **esp32** board package through Boards Manager.
2. Select **ESP32 Dev Module** and the board's USB port.
3. Install **Adafruit GFX Library**, **Adafruit ILI9341**, and **Adafruit Fingerprint Sensor Library**, including their Library Manager dependencies.
4. Open [`campusid-terminal.ino`](firmware/campusid-terminal/campusid-terminal.ino); keep all companion files in the same sketch directory.
5. Verify/compile first. Open Serial Monitor at **115200 baud** after a verified upload; sensor UART runs at **57600 baud**.

**Resolve the display wiring discrepancy before uploading the combined firmware.** The reported working TFT uses CS 5 / DC 2 / RESET 4 / MOSI 23 / CLK 18 / MISO 19 with the explicit six-argument constructor. The combined terminal still uses CS 27 / DC 4 / RESET -1 and a hardware-SPI constructor. GPIO2 is currently assigned to its buzzer. Do not merge those configurations without resolving that conflict.

A new standalone [`tft-regression.ino`](firmware/tft-regression/tft-regression.ino) preserves the reported constructor/pins and draws borders, colors, and bottom text for inspection. It is a reconstructed regression sketch, not the original tested demo, and has not been physically verified here. Refer to the [hardware plan](docs/EXPO_ROADMAP.md) for power, keypad, and pin constraints.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Blank/failed setup | Valid public project URL/key, supported Node, restart Vite |
| Invalid login | Correct Auth account, confirmed email, correct project |
| Account not provisioned | Matching `user_roles.user_id`; teacher must link to `people.id` |
| Empty teacher roster | Teacher role, active person, class assignments, deployed RLS |
| Missing function or attendance table | Apply the complete development database sequence |
| Save unconfirmed | Refresh after reconnect; do not assume a timeout means a failed write |
| TFT blank or cropped | Compare constructor/pins and verify portrait rotation; run standalone regression |
| Random keypad inputs | GPIO34/35 need external 10 kΩ pull-ups, absent from the confirmed inventory |
| Fingerprint never matches | The current firmware recognizes existing templates; it does not enroll new fingers |

## Deliberate prototype limits

No cloud enrollment, trusted device ingestion, Wi-Fi/offline event queue, live terminal telemetry, timetable, payroll, fees, or mobile app. The strongest next milestone is a single demonstrable path: **remote enrollment → authorized class → fingerprint scan → dashboard result → Wi-Fi failure and safe replay**. See the roadmap for acceptance criteria and feasible hardware.
