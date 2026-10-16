# Setup Reference

Use [README.md](./README.md) for the normal fresh-machine walkthrough. This document adds project-specific configuration details and recovery checks without repeating the full onboarding sequence.

## Frontend environment

The frontend reads `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` from `.env.local`; [`.env.example`](./.env.example) is the safe starter template. The second variable name is retained for compatibility and can contain the project's publishable key or legacy anon key. Vite exposes `VITE_*` values in the client bundle, so never place a service-role or other secret key there.

If you change `.env.local` while Vite is running, stop and restart the dev server. A missing or malformed URL should be handled as an app configuration problem; it does not indicate a firmware or database failure.

## Supabase CLI workflow

The repository has no `supabase/config.toml`. CLI linking is for the remote project and is not required to run the frontend. The production project is `erp-fingerprint`, ref `pxophxwlxaqiqfxssoqg`.

After installing the CLI for your platform, authenticate and link from the repository root:

```sh
supabase --version
supabase login
supabase link --project-ref pxophxwlxaqiqfxssoqg
supabase migration list --linked
```

If the CLI is invoked through npm rather than a system install, use `npx supabase --version` and prefix the commands with `npx`.

Before applying a migration or deploying a function, verify that the linked ref is the intended project and review the change. These commands modify hosted state and are not part of routine app startup:

```sh
supabase db push --linked
supabase functions deploy <function-name> --project-ref pxophxwlxaqiqfxssoqg
```

There is currently no `supabase/config.toml` in this checkout. If the CLI requires local project configuration for a migration operation, stop and review the setup rather than initializing or applying changes automatically.

Heartbeat and device-command endpoints authenticate with the device-specific secret header, so their established gateway deployment uses `--no-verify-jwt`. Do not change endpoint authentication settings as part of local setup. Function service-role credentials belong only in the hosted function environment, never in browser configuration or firmware.

## Firmware configuration and startup diagnosis

The Arduino sketch is [campusid-terminal.ino](./firmware/campusid-terminal/campusid-terminal.ino). Arduino compiles its companion source files from the same `firmware/campusid-terminal/` directory. Keep the ignored `secrets.h` there beside `secrets.example.h`.

The template defines the six symbols consumed by `network_service.cpp`: Wi-Fi SSID/password, heartbeat URL, command URL, device secret, and Supabase root CA. If firmware reports missing configuration, first confirm the active sketch path and the local file's presence; compare macro names without copying credential values to Serial or chat. A config-present message does not prove that Wi-Fi credentials, endpoint reachability, TLS trust, or device authentication are valid.

For serial checks, use 115200 baud. The sensor communicates at 57600 baud over UART2: sensor TX to GPIO16 and sensor RX to GPIO17. Windows assigns a COM port; macOS commonly shows a `/dev/cu.*` device. Select the port that appears when the board is connected rather than relying on a fixed name.

When investigating a failed heartbeat, check in this order:

1. The Wi-Fi association status and configured SSID (never log its password).
2. The heartbeat URL host/path and whether the secure request begins successfully.
3. The trusted CA certificate validity and system time/connectivity conditions.
4. The HTTP status. An HTTP authentication failure means the request reached the service but the configured device secret does not match the backend hash.

Do not use `WiFiClientSecure::setInsecure()` to bypass certificate verification. Keep the device secret plaintext only in the ignored local file; the database stores its hash.

## Physical setup checks

Use the pin table in [README.md](./README.md) and verify the board and module silkscreen before applying power. The firmware selects ILI9341, display rotation 2, and the listed TFT SPI pins. GPIO2 is occupied by TFT DC; keypad and buzzer are disabled. Power rails, UART logic levels, current requirements, and common ground must be checked against the actual modules; GPIO pins are not power supplies.

The firmware uses the sensor-reported capacity at runtime. The current tested R307S reported capacity 1000, but another sensor may report a different value. Do not replace the runtime reading with a hardcoded marketing capacity.

### Destructive sensor maintenance

The sketch accepts the Serial command `RESET FINGERPRINT DATABASE`. It clears all fingerprint templates stored on the physical R307S and is not executed automatically at boot. Do not send it during normal setup or troubleshooting unless intentionally erasing the sensor and prepared to re-enroll templates. Backend mappings and sensor templates are separate state; resetting the sensor can leave mappings that no longer correspond to a stored template.

## Additional recovery checks

- If `npm install` or the Vite build reports an unsupported Node version, compare `node --version` with the `engines` range in `package.json`.
- If `supabase migration list --linked` fails, confirm CLI login, the repository root, and the intended linked ref before running write commands.
- If `secrets.h` exists but `WiFi.begin()` is not reached, confirm that the Arduino IDE opened the sketch in this repository, not a stale duplicate folder. Keep only safe serial diagnostics; do not expose macro contents.
- If Wi-Fi connects but HTTPS fails, preserve CA verification and check the endpoint/CA before investigating device authentication. Do not rotate credentials as a first diagnostic step.
- If the screen remains blank, confirm the selected ILI9341 adapter and wiring; verify the display's own power and pin labels rather than assuming its header order.
- If the fingerprint sensor does not become ready, verify suitable sensor power, ground, crossed TX/RX, and 57600 baud. The TFT and ERP setup do not validate UART wiring.

Real `.env.local` and `secrets.h` files are machine-local and ignored. The physical R307S template database is not included in Git or restored by cloning the repository.
