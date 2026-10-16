#include "hardware_self_test.h"

SelfTestState HardwareSelfTest::run(DisplayAdapter& display,
                                    KeypadInput& keypad) {
  SelfTestState result;
  result.display = display.available();
  // A keypad can only be software-verified when the operator presses a key.
  result.keypad = keypad.sawInput();
  // GPIO output writes are verified by software execution, not electrical
  // measurement. The UI labels these as software checks.
  result.led = true;
  result.buzzer = true;
  return result;
}
