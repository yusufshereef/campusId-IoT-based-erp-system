# CampusID expo roadmap and hardware feasibility

The strongest exhibit is a short, convincing demonstration of a complete physical-to-digital workflow. Build one reliable terminal and one excellent class experience before adding conventional ERP modules.

## 1. Critical milestones, in order

| Priority | Feature | Why it stands out | Dependency / acceptance gate |
| --- | --- | --- | --- |
| P0 | Stable combined TFT + R307S terminal | Visitors see a responsive physical product, not separate demos | Resolve actual pins and power; readable portrait display, repeated scans and recoverable sensor errors |
| P0 | Browser-requested enrollment | Register a visitor without reflashing the board | Device authentication, leased enrollment command, two captures, slot acknowledgement and atomic mapping |
| P0 | Authorized session → scan → dashboard | Demonstrates a real IoT ERP round trip | Teacher selects assigned class; gateway validates student/class/duplicate; TFT and browser agree on accepted/rejected outcome |
| P1 | Unplug Wi-Fi, then recover | Makes resilience visible and memorable | Durable ESP32 event queue, stable IDs, trusted session context, idempotent replay, bounded queue and explicit conflict handling |
| P1 | Honest live terminal panel | Judges can see health and data flow | Heartbeat age, firmware version, queue depth, current class, recent accepted/rejected events; label stale data, never fake “online” |
| P2 | Physical presentation and operator diagnostics | Reliability and usability are immediately apparent | Labeled enclosure/panel, readable sensor placement, strain relief, one action to run a clearly labeled self-test |

Remote enrollment and trusted scan ingestion require new backend/schema work; they are designs below, not implemented features. Avoid payroll, fees, library modules, face recognition, mobile apps, predictive analytics and decorative charts for this prototype.

## 2. Enrollment design

Admin selects an active student and terminal. Backend creates an authorized, expiring command with a unique command ID and reserved device/slot identity. The terminal fetches a command using a device-specific credential and shows: **place finger → remove → place again → saving → enrolled**.

Only acknowledge enrollment after the sensor confirms storage and the backend confirms the mapping. If mapping fails after sensor storage, retain the command/result and retry reconciliation; do not report full success. Record abandoned/orphaned slots for administrator recovery. Cancellation, duplicate fingerprints, occupied slots, sensor timeout, and power loss need explicit states. Never automatically erase an existing slot to resolve a conflict.

A template ID belongs to a particular sensor/terminal. Model uniqueness as `(device_id, slot_id)`; a globally unique bare slot ID will fail when a second terminal is introduced. Keep templates in the sensor. Store mappings and operational metadata only in the backend.

## 3. Trusted attendance design

Use the teacher's browser login to select an assigned class and pair a nearby terminal through a short-lived code shown on the TFT. This is feasible with the available TFT/keypad and avoids implementing a second password system on the ESP32. Pairing must require authenticated teacher approval and expire quickly; a visible code alone must not grant class access.

The backend issues a bounded session authorization tied to terminal, teacher and class. The terminal sends device-authenticated events containing a stable event UUID, device ID, session reference, slot ID, sequence and clock-quality metadata. A gateway resolves the slot, validates membership/activation/session and applies database duplicate rules. Return structured accepted/duplicate/wrong-class/unknown/expired results. Do not trust a student ID or teacher ID merely because firmware supplied it.

Never embed a Supabase service-role key in firmware. Prefer a per-device revocable credential scoped to a gateway. Use TLS certificate validation; do not use `setInsecure()` for a polished demo. Pairing and provisioning need a documented recovery process for a lost/compromised board.

For the current single-class-per-day prototype, keep existing daily attendance semantics. If repeated lessons on one date are necessary, explicitly introduce persistent session rows and change uniqueness in a reviewed migration.

## 4. Offline resilience with existing hardware

ESP32 internal flash can support a **small bounded queue**; an SD card is not required for the first demo. Evaluate LittleFS append records/checksums or a journaled NVS design. Persist before reporting “queued locally”, retain records until server acknowledgement, and make replay idempotent. Batch writes and bound queue length to limit flash wear. On full storage, stop accepting scans and show a clear message rather than dropping events.

Cache only the minimum roster/session data needed for the current authorized class. Offline acceptance is provisional: the server revalidates when reconnecting. An expired/revoked session or changed enrollment must become an explicit rejection/conflict, not a silent success.

There is **no RTC listed in the inventory**. Obtain UTC from a trusted server/NTP while online and track elapsed time during the powered session. After a cold boot without trustworthy time, label the clock untrusted and require reconnection/session authorization before timestamp-dependent acceptance. An optional DS3231 can improve offline timekeeping but does not replace authorization or replay validation.

## 5. Available/discussed hardware

The supplied inventory is a discussion record, not a confirmed physical stock check. Only the TFT's standalone working test is explicitly reported. Verify possession, board variants and specifications before assembly.

| Component | Feasible use now | Constraints / missing confirmation |
| --- | --- | --- |
| ESP32 DevKit V1 / WROOM-32 | Controller, Wi-Fi, UART/SPI, small flash queue | USB interface/board revision, power supply capacity and partition size |
| R307S optical reader | On-sensor enrollment/storage/matching | Exact connector, supply voltage/current, UART logic level and slot capacity |
| 2.8-inch 240×320 ILI9341 SPI TFT | Portrait scan/enrollment/status screens | Reported standalone test works; exact backlight/J1 circuit unresolved; touch is not assumed |
| 4×4 membrane keypad | Navigate/select/cancel, optional pairing input | Eight GPIOs; current columns 34/35 require external pull-ups |
| Red/green bi-color LED or separate LEDs | Success/rejection/queued indication | Verify common-cathode/anode; use one 220 Ω resistor per driven LED channel |
| Active buzzer module | Short audible feedback | Verify drive current/polarity; transistor/driver may be required and is not confirmed in inventory |
| 830-point breadboard, M–M/M–F jumpers, headers | Assemble one exhibit terminal | Secure loose connectors; breadboard contacts can cause intermittent power/UART errors |
| 220 Ω resistors | LED current limiting | These are not substitutes for the required keypad 10 kΩ pull-ups |
| Unspecified capacitors | Potential decoupling after selecting suitable values | Values, ratings and quantity unconfirmed; verify rail stability under Wi-Fi load |
| Soldering iron kit | Headers and mechanically stable connections | No additional TFT soldering/J1 changes without verifying the module circuit |

**Likely small additions:** two 10 kΩ resistors if retaining GPIO34/35 keypad columns; a suitable buzzer driver if the module requires one; stable regulated power/USB cable; an enclosure or labeled mounting panel. Confirm those needs against actual hardware. An RTC, SD storage, second reader, camera, relay, motor or new MCU is not necessary for the core expo path.

## 6. Pin conflict that must be resolved

| Signal | Reported working TFT test | Current combined firmware |
| --- | ---: | ---: |
| TFT CS | GPIO5 | GPIO27 |
| TFT DC | GPIO2 | GPIO4 |
| TFT RESET | GPIO4 | Unassigned (`-1`) |
| TFT MOSI | GPIO23 | GPIO23 |
| TFT CLK | GPIO18 | GPIO18 |
| TFT MISO | GPIO19 | Omitted from SPI initialization |
| TFT constructor | Explicit six-argument software SPI | Three-argument hardware SPI |
| Buzzer | Not part of standalone test | GPIO2 — conflicts with working TFT DC |

Preserve the reported working test first. The [regression sketch](../firmware/tft-regression/tft-regression.ino) reconstructs its constructor/pins without touching the terminal configuration. Run it with the buzzer disconnected from GPIO2. It still needs compilation and physical verification.

After confirming current wiring, a possible combined map keeps the working TFT pins and moves the buzzer to the now-free GPIO27, provided that pin is unused on the actual board and the driver circuit is appropriate. This is a **proposal**, not an applied wiring change. GPIO2/5 are boot-strapping pins; check boot/upload behavior with the actual peripheral loads. Do not change power rails or solder J1 to compensate for an unverified constructor/pin mismatch.

R307S remains sensor TX → ESP32 RX16, ESP32 TX17 → sensor RX, 57600 baud with common ground. Current keypad rows are 13/14/25/26, columns 32/33/34/35; LEDs use 21/22. ESP32 signals must be 3.3 V safe. The reported TFT test used 3.3 V power/backlight, but this is not proof of the exact module's current requirements. No peripheral should be powered from a GPIO.

## 7. Display and feedback language

Keep one prominent outcome at a time, with a short action beneath it:

| State | Main message | Secondary detail / feedback |
| --- | --- | --- |
| Ready | Place your finger | Class and session status |
| Recognized, waiting for server | Verifying attendance | Do not play final success yet |
| Accepted | Attendance recorded | Student first name/roll suffix, green + short chirp |
| Duplicate | Already recorded | Previous time; neutral feedback |
| Wrong class | Different class | Ask teacher; red + short rejection |
| Offline, durable write confirmed | Saved on terminal | Pending sync count; amber/text + distinct tone |
| Queue full | Storage full | Reconnect before accepting more scans |
| Clock/session untrusted | Reconnect to continue | Preserve queued events; do not fabricate time |

Use text/icons as well as color. Prefer partial redraw of the status region after integration; the current firmware still clears a full screen on state transitions and may visibly flicker on software SPI. Measure before claiming a target frame rate or scan latency.

## 8. Three-minute exhibit script and acceptance tests

1. **0:00–0:40:** Show a class and student. Request enrollment from the browser; capture two impressions and show verified mapping completion.
2. **0:40–1:20:** Teacher starts the class. Scan once; TFT and dashboard show accepted. Scan again; show duplicate prevention without an extra row.
3. **1:20–2:10:** Disable Wi-Fi. Scan and show “saved on terminal / pending”. Reboot while offline; demonstrate the event is still queued, without pretending the clock/session is trusted.
4. **2:10–2:40:** Reconnect. Drain the queue once, show acknowledgements and unchanged count after a repeated sync.
5. **2:40–3:00:** Show a wrong-class rejection and terminal health/last-sync detail.

The complete script is the **target demo**, not a claim of current functionality. Until the gateway/queue exist, demonstrate only the clearly labeled manual workflow and local sensor recognition.

Record measured results: recognition-to-confirmation latency (median and p95), replay counts, queue survival after power loss, reconnect time, and readable error states. Suggested gates: 20 consecutive valid scans with finger removal, 10 duplicate scans yielding no extra rows, wrong-class/inactive/expired-session rejection, canceled enrollment recovery, lost-response replay, and successful boot with every connected peripheral. Use volunteer demo identities with consent and an explicit template cleanup procedure.
