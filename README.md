# CampusID

CampusID is an IoT fingerprint attendance ERP built with React, TypeScript, and Vite; Supabase Auth, PostgreSQL, and Edge Functions; and an ESP32 DevKit V1 / ESP32-WROOM-32 terminal with an R307S fingerprint sensor and ILI9341 TFT.

Raw fingerprints are never uploaded. Fingerprint templates remain on the R307S; the backend stores mapping metadata only.

## Local Development Setup

Follow these steps to run the ERP and prepare the terminal firmware on a new Windows or macOS machine. `expo-v1` is the current development branch.

### 1. Prerequisites

- Git
- Node.js and npm. The required Node versions are listed in [`package.json`](./package.json) (`engines` field).
- A Supabase project and its project URL and publishable/legacy anon key
- Supabase CLI for project administration
- Arduino IDE 2.x and Espressif ESP32 board support for firmware
- VS Code is optional

On macOS, if Git reports an invalid developer path, install Apple command-line tools with `xcode-select --install`, then open a new terminal.

### 2. Clone the repository

**Windows PowerShell**

```powershell
git clone https://github.com/yusufshereef/campusId-IoT-based-erp-system.git
Set-Location campusId-IoT-based-erp-system
git fetch origin
git switch expo-v1
git branch --show-current
git log -1 --oneline
```

**macOS Terminal**

```sh
git clone https://github.com/yusufshereef/campusId-IoT-based-erp-system.git
cd campusId-IoT-based-erp-system
git fetch origin
git switch expo-v1
git branch --show-current
git log -1 --oneline
```

The branch command should print `expo-v1`. The checkpoint tag `expo-checkpoint-2026-10-17` marks a saved development checkpoint; normal work should continue on `expo-v1`.

### 3. Install and run the frontend

```sh
npm install
```

Create the local environment file.

**Windows PowerShell**

```powershell
Copy-Item .env.example .env.local
```

**macOS / Linux**

```sh
cp .env.example .env.local
```

Edit `.env.local` with the two required values from your Supabase project settings:

```dotenv
VITE_SUPABASE_URL=https://YOUR_PROJECT.supabase.co
VITE_SUPABASE_ANON_KEY=YOUR_PUBLISHABLE_OR_LEGACY_ANON_KEY
```

The `VITE_SUPABASE_ANON_KEY` variable accepts a publishable key or legacy anon key. These frontend values are bundled for browser use: **never use a service-role or secret key here**. `.env.local` is ignored by Git and must not be committed. Restart the dev server after editing it.

Start Vite:

```sh
npm run dev
```

Open the printed local URL, normally <http://localhost:5173>. Useful validation commands:

```sh
npm test
npm run build
```

### 4. Supabase CLI

Install the Supabase CLI using the supported installation method for your OS. Then verify and authenticate it:

```sh
supabase --version
supabase login
supabase link --project-ref pxophxwlxaqiqfxssoqg
supabase migration list --linked
```

If you use an npm-invoked CLI instead of a system command, check it with `npx supabase --version` and prefix subsequent CLI commands with `npx`.

The production project is **erp-fingerprint** (`pxophxwlxaqiqfxssoqg`). Confirm the linked project before running administrative commands. Do not apply migrations or deploy functions unless you are intentionally working on backend changes and have reviewed the target project.

```sh
supabase db push --linked
supabase functions deploy <function-name> --project-ref pxophxwlxaqiqfxssoqg
```

This repository currently has no `supabase/config.toml`; the migration command is shown for intentional backend work, not normal onboarding. If the CLI requires local Supabase project configuration, stop and review that setup before creating/configuring files or applying database changes.

Device-authenticated functions use the gateway setting shown in the existing project setup, for example:

```sh
supabase functions deploy device-heartbeat --no-verify-jwt --project-ref pxophxwlxaqiqfxssoqg
supabase functions deploy device-command --no-verify-jwt --project-ref pxophxwlxaqiqfxssoqg
```

Never put the function service-role key in frontend or firmware configuration. There is no `supabase/config.toml` in this repository.

### 5. Arduino IDE / ESP32 firmware

1. Install Arduino IDE 2.x.
2. In Boards Manager, install Espressif ESP32 board support.
3. Select **ESP32 Dev Module** and the correct serial port. Windows ports may appear as `COM3` or `COM4`; macOS ports commonly appear as `/dev/cu.usbserial-*` or `/dev/cu.SLAB_USBtoUART`. Names vary by adapter and machine.
4. In Library Manager, install:
   - Adafruit GFX Library
   - Adafruit ILI9341
   - Adafruit Fingerprint Sensor Library
5. Open this exact sketch: [`firmware/campusid-terminal/campusid-terminal.ino`](./firmware/campusid-terminal/campusid-terminal.ino). Keep its companion firmware files in the same directory.
6. Create the ignored local `secrets.h` as described below.
7. Verify/compile, check the hardware connections, then upload. Open Serial Monitor at **115200 baud**.

### 6. Local firmware secrets

Copy the tracked placeholder template next to the sketch.

**Windows PowerShell**

```powershell
Copy-Item firmware/campusid-terminal/secrets.example.h firmware/campusid-terminal/secrets.h
```

**macOS / Linux**

```sh
cp firmware/campusid-terminal/secrets.example.h firmware/campusid-terminal/secrets.h
```

Edit the local `secrets.h` with the Wi-Fi SSID/password, the heartbeat and command URLs, the device secret, and the trusted Supabase root CA certificate. Firmware expects these identifiers: `CAMPUSID_WIFI_SSID`, `CAMPUSID_WIFI_PASSWORD`, `CAMPUSID_HEARTBEAT_URL`, `CAMPUSID_COMMAND_URL`, `CAMPUSID_DEVICE_SECRET`, and `CAMPUSID_SUPABASE_ROOT_CA`.

`secrets.h` is ignored by Git. Never commit or print it, Wi-Fi credentials, device secrets, or service-role keys. The backend stores only the device secret hash. Keep certificate validation enabled; never use `WiFiClientSecure::setInsecure()`.

### 7. Verified hardware wiring

These values match the current firmware configuration. Verify the actual module labels, voltage/current requirements, and common ground before connecting power.

| Hardware signal | ESP32 configuration |
| --- | ---: |
| R307S TX → ESP32 UART2 RX | GPIO16 |
| ESP32 UART2 TX → R307S RX | GPIO17 |
| R307S UART | 57600 baud, 8N1 |
| TFT CS | GPIO5 |
| TFT DC | GPIO2 |
| TFT RESET | GPIO4 |
| TFT MOSI | GPIO23 |
| TFT SCK | GPIO18 |
| TFT MISO | GPIO19 |
| TFT rotation | 2 |

The selected display controller is ILI9341. GPIO2 is the TFT DC pin, so the buzzer is disabled. The keypad is also disabled in the current baseline. Do not reuse GPIO2 for the buzzer.

The sensor reports its template capacity at runtime; the current tested R307S reported 1000 templates. Do not assume or hardcode a marketing capacity.

#### Destructive sensor maintenance

The Serial maintenance command `RESET FINGERPRINT DATABASE` clears all templates stored on the R307S. It is **not** run automatically at boot. Do not send it during ordinary setup; use it only when deliberately resetting the physical sensor and after confirming that clearing its templates is intended.

### 8. Troubleshooting

- **Vite setup/configuration error:** check both `VITE_*` entries in `.env.local`, confirm they belong to the intended Supabase project, and restart Vite.
- **Login/account not provisioned:** verify the Auth account and role/person linkage in the intended project.
- **CLI is linked to the wrong project:** inspect the linked project before any writes; re-link only to the intended project.
- **No network configuration in firmware:** confirm the sketch path and that ignored `secrets.h` is beside the sketch with all six required macro names. Do not print their values.
- **Wi-Fi or heartbeat failure:** check local Wi-Fi values, endpoint URLs, CA certificate, and the provisioned device secret/hash pair. Do not weaken TLS validation.
- **Fingerprint sensor not ready:** verify sensor power/common ground, crossed UART direction (sensor TX to GPIO16; sensor RX to GPIO17), and 57600 baud.
- **TFT blank or wrong orientation:** verify ILI9341 selection, the pin map above, the module's labeled pins and power requirements, and rotation 2. Do not assume the display connector pin order.
- **Arduino upload fails:** check ESP32 board support, **ESP32 Dev Module**, the selected serial port, USB cable, and required libraries.

## New Machine Checklist

- [ ] Install Git, Node.js/npm, Arduino IDE 2.x, and ESP32 board support as needed.
- [ ] Clone the repo, run `git fetch origin`, and switch to `expo-v1`.
- [ ] Run `npm install`.
- [ ] Copy `.env.example` to `.env.local` and enter the browser-safe Supabase URL/key.
- [ ] Run `npm run dev` and confirm the ERP opens.
- [ ] Install/authenticate Supabase CLI and link the intended project when cloud administration is needed.
- [ ] Install the three listed Arduino libraries.
- [ ] Copy `secrets.example.h` to `secrets.h` and fill local Wi-Fi/device/endpoint/CA configuration.
- [ ] Verify wiring, select **ESP32 Dev Module** and the correct serial port, then use Verify and Upload.
- [ ] Open Serial Monitor at 115200 baud; confirm the sensor is ready, heartbeat returns HTTP 200, and the ERP reports the terminal online.

For expanded setup notes and troubleshooting, see [SETUP.md](./SETUP.md). For current development status, see [docs/DEVELOPMENT_CHECKPOINT.md](./docs/DEVELOPMENT_CHECKPOINT.md).

## More documentation

- [Firmware wiring and implementation notes](./firmware/campusid-terminal/README.md)
- [Implementation and design](./docs/IMPLEMENTATION.md)
- [Hardware feasibility and expo roadmap](./docs/EXPO_ROADMAP.md)
- [Disposable database tests](./supabase/test/README.md)
- [Earlier engineering/security history](./docs/ENGINEERING_PLAN.md)
