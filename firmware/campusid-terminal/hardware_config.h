#pragma once

// Phase 1 terminal configuration. Verify every pin against the actual board
// and module before applying power.

#define CAMPUSID_FIRMWARE_VERSION "0.1.0"
#define CAMPUSID_DEVICE_ID "CAMPUSID-TERMINAL-01"

// KTRON 2.8-inch 240x320 SPI non-touch module: ILI9341.
// ILI9341 is the selected default for the ordered display.
#define CAMPUSID_DISPLAY_ILI9341 1
// Optional alternate adapter for a different, verified module only.
#define CAMPUSID_DISPLAY_ST7789 0

#if CAMPUSID_DISPLAY_ILI9341 == CAMPUSID_DISPLAY_ST7789
#error "Select exactly one display controller"
#endif

namespace CampusIdPins {
constexpr int TftSck = 18;
constexpr int TftMosi = 23;
constexpr int TftCs = 27;
constexpr int TftDc = 4;
// The ordered module's reset wiring is not verified. -1 leaves reset
// unassigned; set this to a verified GPIO only with the module documentation.
constexpr int TftReset = -1;

// GPIO34 and GPIO35 are input-only and have no internal pull resistors.
// Use external 10K pull-ups for those keypad columns.
constexpr int KeypadRow0 = 13;
constexpr int KeypadRow1 = 14;
constexpr int KeypadRow2 = 25;
constexpr int KeypadRow3 = 26;
constexpr int KeypadCol0 = 32;
constexpr int KeypadCol1 = 33;
constexpr int KeypadCol2 = 34;
constexpr int KeypadCol3 = 35;

constexpr int GreenLed = 21;
constexpr int RedLed = 22;
constexpr int Buzzer = 2;

// R307S UART2 connection: sensor TX -> ESP32 RX, sensor RX -> ESP32 TX.
constexpr int R307Rx = 16;
constexpr int R307Tx = 17;
}

namespace CampusIdDisplay {
constexpr int Width = 240;
constexpr int Height = 320;
// The screens below use a 240x320 portrait coordinate system.
constexpr int Rotation = 0;
constexpr uint16_t Background = 0x1082;
constexpr uint16_t Panel = 0x2128;
constexpr uint16_t Accent = 0x05BF;
constexpr uint16_t Success = 0x2D66;
constexpr uint16_t Warning = 0xFD60;
constexpr uint16_t Error = 0xE8A4;
constexpr uint16_t Text = 0xFFFF;
constexpr uint16_t Muted = 0xB596;
}
