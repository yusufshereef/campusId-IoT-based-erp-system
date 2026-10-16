#pragma once

#include <Arduino.h>
#include "hardware_config.h"

class DisplayAdapter {
 public:
  bool begin();
  void clear(uint16_t color = CampusIdDisplay::Background);
  void header(const char* title, const char* subtitle = nullptr);
  void text(const char* value, int16_t x, int16_t y, uint8_t size = 1,
            uint16_t color = CampusIdDisplay::Text);
  void line(int16_t x, int16_t y, int16_t width, uint16_t color);
  void panel(int16_t x, int16_t y, int16_t width, int16_t height,
             uint16_t color = CampusIdDisplay::Panel);
  bool available() const { return initialized_; }

 private:
  bool initialized_ = false;
};
