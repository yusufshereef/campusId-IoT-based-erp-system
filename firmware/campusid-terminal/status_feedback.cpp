#include "status_feedback.h"

void StatusFeedback::begin() {
  pinMode(CampusIdPins::GreenLed, OUTPUT);
  pinMode(CampusIdPins::RedLed, OUTPUT);
#if ENABLE_BUZZER
  pinMode(CampusIdPins::Buzzer, OUTPUT);
#endif
  output(false, false);
}

void StatusFeedback::output(bool led, bool buzzer) {
  digitalWrite(CampusIdPins::GreenLed,
               led && kind_ == FeedbackKind::Success ? HIGH : LOW);
  digitalWrite(CampusIdPins::RedLed,
               led && kind_ != FeedbackKind::Success ? HIGH : LOW);
#if ENABLE_BUZZER
  digitalWrite(CampusIdPins::Buzzer, buzzer ? HIGH : LOW);
#else
  (void)buzzer;
#endif
}

void StatusFeedback::play(FeedbackKind kind) {
  kind_ = kind;
  active_ = true;
  led_on_ = true;
  step_ = 0;
  next_step_ = millis();
}

void StatusFeedback::update() {
  if (!active_ || static_cast<int32_t>(millis() - next_step_) < 0) return;
  if (kind_ == FeedbackKind::Success) {
    output(led_on_, led_on_);
    led_on_ = !led_on_;
    step_++;
    if (step_ >= 4) active_ = false;
    next_step_ = millis() + 90;
  } else if (kind_ == FeedbackKind::Rejected) {
    // Keep the output on until the next scheduled step; do not clear it
    // in the same loop iteration that starts the rejection pulse.
    if (step_ == 0) {
      output(true, true);
      step_++;
      next_step_ = millis() + 180;
    } else {
      active_ = false;
    }
  } else {
    output(led_on_, false);
    led_on_ = !led_on_;
    step_++;
    if (step_ >= 3) active_ = false;
    next_step_ = millis() + 140;
  }
  if (!active_) output(false, false);
}
