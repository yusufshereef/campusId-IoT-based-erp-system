# CampusID Development Checkpoint

Branch: `expo-v1`

## Current working architecture

- React/TypeScript/Vite ERP
- Supabase project ref `pxophxwlxaqiqfxssoqg`
- ESP32 + R307S + ILI9341 terminal
- Remote heartbeat works; TLS and device authentication are enabled
- Remote fingerprint enrollment, slot reservation, stale command recovery, and safe student/teacher/class deletion are implemented
- Sensor reports capacity 1000

## Verified hardware

R307S: sensor TX → GPIO16, sensor RX → GPIO17, 57600 baud

TFT: CS 5, DC 2, RST 4, MOSI 23, SCK 18, MISO 19, rotation 2

## Current product state

Working: heartbeat HTTP 200, terminal online/offline status, known/unknown fingerprint matching, remote enrollment, Template #1/#2 enrollment, enrollment failure states, slot reservation, stale command recovery, and safe student/teacher/class delete RPCs.

One test student produced “Fingerprints did not match; try again”. Treat this as a capture-quality mismatch, not as an overall enrollment failure.

## Current / next work

Admin Delete Fingerprint; admin Re-enroll; safe deletion of an enrolled student after physical template removal; persistent class sessions; fingerprint attendance validation; live session updates; offline attendance queue/replay; final expo polish.

## New machine setup

1. Clone the repository and run `git switch expo-v1`.
2. Run `npm install`.
3. Copy `.env.example` to `.env.local` and fill in local values.
4. Copy `firmware/campusid-terminal/secrets.example.h` to `firmware/campusid-terminal/secrets.h` and fill in local Wi-Fi/device values and the CA certificate.
5. Install ESP32 Arduino board support and required libraries.
6. Link/login the Supabase CLI if cloud administration is needed.
7. Run `npm run dev`.
8. Use Arduino Verify + Upload when firmware changes.

`secrets.h` and `.env.local` are local only. Real R307S templates are physical-device state and are not stored in Git.
