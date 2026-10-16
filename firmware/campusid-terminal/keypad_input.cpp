#include "keypad_input.h"

namespace {
constexpr int Rows[] = {
    CampusIdPins::KeypadRow0, CampusIdPins::KeypadRow1,
    CampusIdPins::KeypadRow2, CampusIdPins::KeypadRow3};
constexpr int Columns[] = {
    CampusIdPins::KeypadCol0, CampusIdPins::KeypadCol1,
    CampusIdPins::KeypadCol2, CampusIdPins::KeypadCol3};
}

void KeypadInput::begin() {
  for (int row : Rows) {
    pinMode(row, OUTPUT);
    digitalWrite(row, HIGH);
  }
  pinMode(CampusIdPins::KeypadCol0, INPUT_PULLUP);
  pinMode(CampusIdPins::KeypadCol1, INPUT_PULLUP);
  pinMode(CampusIdPins::KeypadCol2, INPUT_PULLUP);
  // GPIO34/35 have no internal pull-up. External resistors are required.
  pinMode(CampusIdPins::KeypadCol2, INPUT);
  pinMode(CampusIdPins::KeypadCol3, INPUT);
}

Key keyFor(int row, int column) {
  if (row == 0 && column == 1) return Key::Up;
  if (row == 1 && column == 1) return Key::Down;
  if (row == 1 && column == 0) return Key::Left;
  if (row == 1 && column == 2) return Key::Right;
  if (row == 2 && column == 1) return Key::Select;
  if (row == 3 && column == 0) return Key::Back;
  if (row == 3 && column == 1) return Key::Test;
  if (row == 3 && column == 2) return Key::Status;
  if (row == 3 && column == 3) return Key::About;
  return Key::Unknown;
}

Key KeypadInput::scan() {
  for (int row = 0; row < 4; row++) {
    for (int current : Rows) digitalWrite(current, HIGH);
    digitalWrite(Rows[row], LOW);
    delayMicroseconds(5);
    for (int column = 0; column < 4; column++) {
      if (digitalRead(Columns[column]) == LOW) {
        for (int current : Rows) digitalWrite(current, HIGH);
        return keyFor(row, column);
      }
    }
  }
  for (int current : Rows) digitalWrite(current, HIGH);
  return Key::None;
}

Key KeypadInput::poll() {
  static Key previous = Key::None;
  static uint32_t last_scan = 0;
  if (millis() - last_scan < 35) return Key::None;
  last_scan = millis();
  const Key current = scan();
  if (current == Key::None) {
    previous = Key::None;
    return Key::None;
  }
  if (current == previous) return Key::None;
  previous = current;
  saw_input_ = true;
  return current;
}
