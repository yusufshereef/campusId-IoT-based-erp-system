#pragma once

#include <Arduino.h>
#include "hardware_config.h"

enum class FeedbackKind { Success, Rejected, Warning };

class StatusFeedback {
 public:
  void begin();
  void play(FeedbackKind kind);
  void update();
  bool active() const { return active_; }

 private:
  bool active_ = false;
  bool led_on_ = false;
  uint8_t step_ = 0;
  uint32_t next_step_ = 0;
  FeedbackKind kind_ = FeedbackKind::Warning;
  void output(bool led, bool buzzer);
};
