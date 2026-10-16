#pragma once

#include <Arduino.h>
#include "hardware_config.h"

enum class Key {
  None,
  Up,
  Down,
  Left,
  Right,
  Select,
  Back,
  Test,
  Status,
  About,
  Unknown
};

class KeypadInput {
 public:
  void begin();
  Key poll();
  bool sawInput() const { return saw_input_; }

 private:
  bool saw_input_ = false;
  Key scan();
};
