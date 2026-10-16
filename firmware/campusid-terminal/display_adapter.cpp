#include "display_adapter.h"

#include <SPI.h>
#include <Adafruit_GFX.h>

#if CAMPUSID_DISPLAY_ST7789
#include <Adafruit_ST7789.h>
static Adafruit_ST7789 display(
    CampusIdPins::TftCs, CampusIdPins::TftDc, CampusIdPins::TftReset);
#elif CAMPUSID_DISPLAY_ILI9341
#include <Adafruit_ILI9341.h>
static Adafruit_ILI9341 display(
    CampusIdPins::TftCs, CampusIdPins::TftDc, CampusIdPins::TftReset);
#endif

bool DisplayAdapter::begin() {
  SPI.begin(CampusIdPins::TftSck, -1, CampusIdPins::TftMosi,
            CampusIdPins::TftCs);
#if CAMPUSID_DISPLAY_ST7789
  display.init(CampusIdDisplay::Width, CampusIdDisplay::Height);
#else
  display.begin();
#endif
  display.setRotation(CampusIdDisplay::Rotation);
  display.fillScreen(CampusIdDisplay::Background);
  display.setTextWrap(false);
  initialized_ = true;
  return initialized_;
}

void DisplayAdapter::clear(uint16_t color) {
  if (initialized_) display.fillScreen(color);
}

void DisplayAdapter::header(const char* title, const char* subtitle) {
  if (!initialized_) return;
  display.fillRect(0, 0, CampusIdDisplay::Width, 42, CampusIdDisplay::Panel);
  text(title, 10, 8, 2, CampusIdDisplay::Text);
  if (subtitle) text(subtitle, 10, 27, 1, CampusIdDisplay::Muted);
}

void DisplayAdapter::text(const char* value, int16_t x, int16_t y,
                          uint8_t size, uint16_t color) {
  if (!initialized_ || value == nullptr || size == 0 ||
      x < 0 || y < 0 || x >= CampusIdDisplay::Width ||
      y >= CampusIdDisplay::Height) {
    return;
  }
  display.setCursor(x, y);
  display.setTextColor(color);
  display.setTextSize(size);
  display.print(value);
}

void DisplayAdapter::line(int16_t x, int16_t y, int16_t width,
                          uint16_t color) {
  if (!initialized_ || width <= 0 || y < 0 || y >= CampusIdDisplay::Height ||
      x >= CampusIdDisplay::Width || x + width <= 0) {
    return;
  }
  const int16_t clipped_x = x < 0 ? 0 : x;
  const int16_t clipped_end = (x + width) > CampusIdDisplay::Width
                                  ? CampusIdDisplay::Width
                                  : x + width;
  display.drawFastHLine(clipped_x, y, clipped_end - clipped_x, color);
}

void DisplayAdapter::panel(int16_t x, int16_t y, int16_t width, int16_t height,
                           uint16_t color) {
  if (!initialized_ || width <= 0 || height <= 0 ||
      x >= CampusIdDisplay::Width || y >= CampusIdDisplay::Height ||
      x + width <= 0 || y + height <= 0) {
    return;
  }
  const int16_t clipped_x = x < 0 ? 0 : x;
  const int16_t clipped_y = y < 0 ? 0 : y;
  const int16_t clipped_right = (x + width) > CampusIdDisplay::Width
                                    ? CampusIdDisplay::Width
                                    : x + width;
  const int16_t clipped_bottom = (y + height) > CampusIdDisplay::Height
                                     ? CampusIdDisplay::Height
                                     : y + height;
  display.fillRoundRect(clipped_x, clipped_y, clipped_right - clipped_x,
                        clipped_bottom - clipped_y, 5, color);
}
