# CampusID ESP32 Terminal — Phase 2

## October 16 review: read before uploading

The user's reported working TFT configuration differs from this combined
firmware: **CS 5 / DC 2 / RESET 4 / MOSI 23 / CLK 18 / MISO 19**, with the
explicit six-argument Adafruit constructor. This directory still uses **CS 27 /
DC 4 / RESET -1** and hardware SPI. Its buzzer uses GPIO2, which conflicts with
the working TFT DC. Do not combine the two pin maps without resolving that
conflict. See the [hardware plan](../../docs/EXPO_ROADMAP.md) and reconstructed
[standalone regression sketch](../tft-regression/tft-regression.ino).

The current screens now use portrait rotation 0 to match their 240×320
coordinates. Rejection feedback now holds its pulse for 180 ms, and poor
fingerprint images take the removal/retry path. These source changes have not
been compiled or physically verified in this review; Arduino CLI was unavailable.

`DisplayAdapter::available()` means the library initialization ran. It cannot
detect an unplugged/blank TFT, and software GPIO writes cannot prove that a
physical LED or buzzer worked. Inspect the outputs during the physical test.

This directory contains the standalone Arduino IDE firmware for the CampusID
terminal. Phase 2 adds local R307S recognition only. It does **not** communicate
with Supabase, create attendance records, authenticate a device, or synchronize
events. Student mapping, authorized sessions, and attendance remain later
phases.

## Hardware and display configuration

- Board: ESP32-WROOM-32 development board.
- Ordered display: KTRON 2.8-inch, 240x320, non-touch SPI TFT.
- Controller selected in this firmware: **ILI9341**.
- The product listing identifies the driver as ILI9341. The firmware selects
  `CAMPUSID_DISPLAY_ILI9341 1` and `CAMPUSID_DISPLAY_ST7789 0`.
- ST7789 support remains available only for a different, separately verified
  display. It is not selected for the ordered KTRON module.
- The product page content available to this project does not provide a
  verified module pinout or signal-level tolerance table. Check the received
  board's silkscreen and documentation before wiring.
- Confirm the display logic voltage and backlight requirements. Do not power a
  backlight from an ESP32 GPIO.

The selected firmware requires Adafruit GFX Library and Adafruit ILI9341.
Adafruit ST7789 and ST7735 Library is needed only if the alternate ST7789
configuration is deliberately selected for another module.

## Arduino IDE setup

1. Install the Espressif ESP32 board package.
2. Select an ESP32-WROOM-32-compatible board, such as **ESP32 Dev Module**.
3. Select the correct USB port and a 115200 baud serial monitor.
4. Install these libraries from Library Manager:
   - Adafruit GFX Library
   - Adafruit ILI9341
5. Open `campusid-terminal.ino`. Keep all files in this directory so Arduino
   compiles the companion `.cpp` and `.h` modules.
6. Compile and upload only after verifying the display controller, voltage,
   ground, and pin wiring.

## ESP32-side pin map

| Function | ESP32 GPIO | Notes |
| --- | ---: | --- |
| TFT SCK | 18 | VSPI clock |
| TFT MOSI | 23 | VSPI MOSI |
| TFT CS | 27 | Display chip select |
| TFT DC | 4 | Display data/command |
| TFT RESET | Configurable, default unassigned | `TftReset = -1`; assign only after verifying module documentation |
| Keypad rows | 13, 14, 25, 26 | Outputs |
| Keypad columns | 32, 33, 34, 35 | Inputs |
| Green LED | 21 | Use a series resistor and transistor if required |
| Red LED | 22 | Use a series resistor and transistor if required |
| Active buzzer | 2 | Use a transistor/driver if current exceeds GPIO limits |
| R307S sensor TX -> ESP32 RX | 16 | UART2 RX, 57600 8N1 |
| ESP32 TX -> R307S sensor RX | 17 | UART2 TX, 57600 8N1 |

GPIO34 and GPIO35 are input-only and have no internal pull-up resistors.
Provide an external 10K pull-up from each of those keypad columns to 3.3 V.
The keypad must not apply 5 V to ESP32 GPIOs.

GPIO2 is an ESP32 boot-strapping pin. The firmware initializes it LOW before
use, but the buzzer circuit must not force it HIGH during reset or flashing.
If the physical buzzer circuit cannot satisfy that requirement, move the
buzzer to another verified-safe GPIO and update `hardware_config.h`.

GPIO4 is also used by the TFT DC line and must not be reused. Do not power the
TFT, backlight, sensor, LEDs, or buzzer from a GPIO output. Use a suitable
regulated supply, common ground, current limiting, and a transistor/driver
where the load requires it. Verify the R307S voltage, current, and UART-level
requirements before wiring.

The configured sensor direction is R307S TX to ESP32 GPIO16 and ESP32 GPIO17
to R307S RX. The sensor's power must come from a suitable regulated supply,
not an ESP32 GPIO.

## Display wiring

The firmware-side SPI mapping is:

| ESP32 signal | Firmware GPIO | Connect to the module signal only after verifying its label |
| --- | ---: | --- |
| SCK | 18 | `SCK` or `CLK` |
| MOSI | 23 | `MOSI`, `SDA`, or equivalent SPI data-in label |
| CS | 27 | `CS` or `LCD_CS` |
| Data/command | 4 | `DC`, `D/C`, or `RS` |
| Reset | Not assigned | `RST`/`RESET` only if the module requires an external reset connection |
| Logic power | 3.3 V | `VCC` only after verifying the board's power requirements |
| Ground | GND | `GND` |
| Backlight | Separate suitable supply/control | `LED`/`BL` only according to module documentation |

These are standard signal-name possibilities, not a claim about the KTRON
board's exact silkscreen. Do not connect by position or color. The listing's
3.3–5 V input rating does not prove that every signal pin is 5 V tolerant.
Use ESP32 3.3 V logic for SCK, MOSI, CS, and DC, and verify the module's
pinout, logic thresholds, reset requirements, and backlight current before
connecting power.

## Wiring checklist

1. Power off the ESP32 before wiring.
2. Connect a common ground first.
3. Inspect the received TFT silkscreen and verify each module pin against its
   documentation; the product listing does not establish the pin order.
4. Verify the TFT's VCC/logic voltage, signal thresholds, reset behavior, and
   backlight current from the module documentation.
5. Connect only the verified TFT SPI/control signals according to the tables.
6. Wire keypad rows/columns; add the required external pull-ups on GPIO34/35.
7. Connect LEDs through resistors and confirm polarity.
8. Drive the active buzzer through an appropriate transistor if its current
   exceeds the ESP32 GPIO recommendation.
9. Connect R307S TX to GPIO16 and R307S RX to GPIO17 only after verifying
   voltage levels and the sensor connector labels.
10. Check for shorts and measure rails before connecting the board.

## Phase 1 behavior

- Boot screen with firmware version and initialization progress.
- Home screen with device identity and local fingerprint recognition state.
- Fingerprint states for initializing, ready, scanning, matched, no-match,
  sensor error, and waiting for removal.
- Match screens show only the sensor template ID and confidence; neither value
  is interpreted as a student identity.
- Display updates are state-driven rather than redrawing on every main-loop
  iteration.
- Keypad menu:
  - Home
  - Hardware Test
  - Device Status
  - About
- Non-blocking success, rejection, and warning feedback patterns.
- Hardware test labels LED/buzzer checks as software checks. It does not claim
  to electrically measure an LED or buzzer.
- Keypad is reported as `PASS` only after an operator presses a key.
- R307S recognition reports only the sensor template ID and confidence.
- No fingerprint enrollment, deletion, attendance record, cloud
  synchronization, student mapping, or device authorization is implemented.

## R307S Phase 2 setup

Install this additional Arduino library from Library Manager:

- Adafruit Fingerprint Sensor Library

The service initializes ESP32 UART2 with:

```text
57600 baud, 8 data bits, no parity, 1 stop bit
RX: GPIO16 (sensor TX)
TX: GPIO17 (sensor RX)
```

The existing sensor template remains untouched. The firmware never calls
enrollment, deletion, overwrite, or clear operations. A successful recognition
is reported locally as:

```text
Fingerprint matched: template_id=1 confidence=...
Recognition only: no student mapping or attendance was created.
```

The result is not interpreted as a student identity. A finger must be removed
before the next recognition cycle is allowed, preventing repeated matches from
one continuous placement.

## TFT runtime behavior

The ILI9341 adapter initializes the display on the configured VSPI signals and
guards drawing through `DisplayAdapter::available()`. Fingerprint recognition
remains independent of the display; if the TFT is disconnected or unusable,
the UART2 sensor loop continues and Serial remains the observation interface.

The display reset pin is intentionally unassigned by default because the
ordered module's reset wiring has not been verified. The adapter uses
`CampusIdPins::TftReset`; leave it at `-1` unless the received module
documentation confirms a safe ESP32 GPIO and reset sequence.

## Compile and upload

1. Install the ESP32 board package and select an ESP32 Dev Module.
2. Install Adafruit GFX Library and Adafruit ILI9341 for the display.
3. Install Adafruit Fingerprint Sensor Library.
4. Open `campusid-terminal.ino` with all firmware files in this directory.
5. Connect the R307S with verified power and crossed UART data lines.
6. Compile for **ESP32 Dev Module**. Do not upload until wiring has been
   checked.
7. Upload only when you are ready to perform the physical test.
8. Open Serial Monitor at 115200 baud.

The TFT, keypad, LEDs, and buzzer may remain disconnected for this sensor-only
check. The firmware keeps its display calls guarded by the display adapter, but
Serial is the authoritative Phase 2 observation interface.

Expected startup output includes:

```text
CampusID terminal boot
R307S UART2 RX GPIO16 TX GPIO17 at 57600 baud
Fingerprint sensor: ready
Fingerprint state: scanning
Fingerprint matched: template_id=1 confidence=...
Recognition only: no student mapping or attendance was created.
```

If the sensor is unavailable, the firmware reports `sensor unavailable` and
retries every five seconds. Communication errors are reported once per state
transition rather than on every loop iteration. Check power, common ground,
crossed TX/RX wiring, UART levels, baud rate, and the sensor connector labels.

## Physical verification checklist

After compiling and uploading:

1. Confirm the serial monitor opens at 115200 baud.
2. Confirm the received module is the listed ILI9341 240x320 display and that
   each connected signal matches its verified label; if the screen stays blank
   or colors/rotation are wrong, stop and recheck wiring and power.
3. Confirm the boot screen is readable and does not flicker.
4. Press the keypad keys and verify menu navigation.
5. Open Hardware Test and verify the pressed-key state changes to `PASS`.
6. Confirm green, red, and buzzer patterns are short and non-blocking.
7. Confirm reset and upload still work with the buzzer and LEDs attached.
8. Confirm no component becomes hot and measure supply voltage under load.
9. Do not interpret local recognition as attendance. R307S enrollment, student
   mapping, device authentication, session authorization, server writes, and
   offline synchronization remain separate work.
