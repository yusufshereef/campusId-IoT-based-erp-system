# CampusID Local Setup

This guide covers the current React/Vite app and ESP32 terminal from a fresh machine. The app uses a Supabase project for authentication and data; the firmware uses a separate local configuration file for Wi-Fi and device authentication.

## Requirements

- Git
- Node.js matching the `engines` range in `package.json` and npm
- A Supabase project and its browser-safe project URL and publishable (or legacy anon) key
- For firmware: Arduino IDE, Espressif ESP32 board support, and the libraries listed below
- For cloud administration with the Supabase CLI: install the CLI for your OS and authenticate it

The repository does not contain a `supabase/config.toml`; the CLI is optional for running the frontend and firmware. Do not put a service-role key in the frontend or firmware.

## Get the project and run the frontend

### Windows PowerShell

```powershell
git clone https://github.com/yusufshereef/campusId-IoT-based-erp-system.git
Set-Location campusId-IoT-based-erp-system
git switch expo-v1
npm ci
Copy-Item .env.example .env.local
npm run dev
```

### macOS Terminal

```sh
git clone https://github.com/yusufshereef/campusId-IoT-based-erp-system.git
cd campusId-IoT-based-erp-system
git switch expo-v1
npm ci
cp .env.example .env.local
npm run dev
```

Edit `.env.local` with values from your Supabase project:

```dotenv
VITE_SUPABASE_URL=https://YOUR_PROJECT.supabase.co
VITE_SUPABASE_ANON_KEY=YOUR_PUBLISHABLE_OR_LEGACY_ANON_KEY
```

The two names above are the frontend's required Vite variables. The key is delivered to the browser, so use only a publishable/anon key. `.env.local` is ignored by Git. Restart the Vite dev server after changing it. Open the local URL printed by `npm run dev`.

## Supabase CLI (optional)

The CLI is for project administration; it is not needed for `npm run dev`. Install the Supabase CLI using its current installation method for Windows or macOS, then authenticate and link the working directory when needed:

```sh
supabase login
supabase link --project-ref pxophxwlxaqiqfxssoqg
```

PowerShell uses the same CLI commands after installation. The project reference is `pxophxwlxaqiqfxssoqg`. No database migration or Edge Function deployment is performed by this setup guide. Use a development project for local development and a separate disposable project for SQL tests. Review the project's existing migration history before applying schema changes.

## Arduino IDE and ESP32 firmware

1. Install Arduino IDE and Espressif ESP32 board support using Boards Manager.
2. Select **ESP32 Dev Module** and the connected board's USB port.
3. Install these libraries with Arduino Library Manager:
   - Adafruit GFX Library
   - Adafruit ILI9341
   - Adafruit Fingerprint Sensor Library
4. Open this exact sketch: `firmware/campusid-terminal/campusid-terminal.ino`.
5. Keep the companion `.cpp` and `.h` files in `firmware/campusid-terminal/` so the sketch can compile them.
6. Copy `firmware/campusid-terminal/secrets.example.h` to `firmware/campusid-terminal/secrets.h` and edit the local copy as described below.
7. Select **ESP32 Dev Module**, verify/compile, then upload when the hardware is wired and checked. Open Serial Monitor at **115200 baud**. R307S UART is **57600 baud**.

### Private firmware configuration

The ignored local `secrets.h` must define the macros used by firmware:

- `CAMPUSID_WIFI_SSID`
- `CAMPUSID_WIFI_PASSWORD`
- `CAMPUSID_HEARTBEAT_URL`
- `CAMPUSID_COMMAND_URL`
- `CAMPUSID_DEVICE_SECRET`
- `CAMPUSID_SUPABASE_ROOT_CA`

The example template contains the current project endpoint paths. Replace Wi-Fi and device placeholders locally, and provide the trusted HTTPS CA certificate in the expected C string format. Keep the real file private: do not paste its contents into logs, commit it, or share it. The backend stores the device secret hash; firmware uses the corresponding local plaintext device secret. Never use `setInsecure()` or a Supabase service-role key in firmware.

Windows copy command:

```powershell
Copy-Item firmware/campusid-terminal/secrets.example.h firmware/campusid-terminal/secrets.h
```

macOS copy command:

```sh
cp firmware/campusid-terminal/secrets.example.h firmware/campusid-terminal/secrets.h
```

## Verified terminal wiring

Pin assignments below are the current firmware configuration. Confirm module labels, voltage, current requirements, and common ground before connecting power.

| Device signal | ESP32 connection |
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

The selected display driver is ILI9341. The keypad and buzzer are disabled in the current hardware configuration; GPIO2 is used by the TFT DC signal. Do not connect the buzzer to GPIO2 in this setup.

## Troubleshooting

- **Vite reports missing Supabase configuration:** verify `.env.local` contains the two required `VITE_*` keys and restart `npm run dev`.
- **Authentication or project errors:** check that the URL and browser-safe key belong to the intended Supabase project and that the account is provisioned there.
- **CLI says the directory is not linked:** run `supabase login`, then `supabase link --project-ref pxophxwlxaqiqfxssoqg` from the repository root.
- **Firmware reports missing network configuration:** confirm the active sketch is `firmware/campusid-terminal/campusid-terminal.ino`, and that `secrets.h` is beside it with all six expected macro names. Do not print the macro values while debugging.
- **Wi-Fi does not connect:** check local SSID/password, 2.4 GHz network availability, board power, and serial output at 115200 baud.
- **Heartbeat TLS/authentication fails:** verify the heartbeat URL, CA certificate, and locally configured device secret; verify that the backend device record uses the hash for that secret. Do not disable certificate validation.
- **Fingerprint sensor is unavailable:** check suitable sensor power, common ground, crossed TX/RX wiring (sensor TX to GPIO16, sensor RX to GPIO17), and 57600 baud.
- **TFT is blank or incorrect:** verify ILI9341 selection, module labels, power, common ground, and the pin map above. Stop and recheck wiring if the module pinout is uncertain.
- **Upload fails:** confirm ESP32 board support, **ESP32 Dev Module**, USB port, cable, and required libraries.

## New-machine checklist

- [ ] Clone the repository and switch to `expo-v1`.
- [ ] Install a Node.js version allowed by `package.json` and run `npm ci`.
- [ ] Copy `.env.example` to `.env.local`, fill the local Supabase URL/key, and keep it untracked.
- [ ] Run `npm run dev` and confirm the app opens.
- [ ] If administering Supabase, install/authenticate the CLI and link the intended project.
- [ ] Install Arduino IDE, ESP32 board support, and the three required Adafruit libraries.
- [ ] Copy `secrets.example.h` to `secrets.h`; fill local Wi-Fi/device settings and CA certificate without committing the file.
- [ ] Open the exact sketch path above and select **ESP32 Dev Module**.
- [ ] Verify wiring and power against the table; use Serial Monitor at 115200 baud after upload.

`.env.local` and `secrets.h` are machine-local configuration. R307S fingerprint templates are stored on the physical sensor and are not reproduced by cloning the repository.
