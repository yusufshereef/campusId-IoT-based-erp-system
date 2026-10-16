#pragma once

#include <Arduino.h>
#include "display_adapter.h"
#include "keypad_input.h"

struct SelfTestState {
  bool display = false;
  bool keypad = false;
  bool led = false;
  bool buzzer = false;
};

class HardwareSelfTest {
 public:
  SelfTestState run(DisplayAdapter& display, KeypadInput& keypad);
};
