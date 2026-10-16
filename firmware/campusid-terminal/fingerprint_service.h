#pragma once

#include <Adafruit_Fingerprint.h>
#include <Arduino.h>

#include "hardware_config.h"

enum class FingerprintState {
  Initializing,
  Ready,
  SensorUnavailable,
  Scanning,
  // Matched and NoMatch are the Result phase before removal is checked.
  Matched,
  NoMatch,
  CommunicationError,
  WaitingForRemoval,
};

struct FingerprintMatch {
  uint16_t template_id = 0;
  uint16_t confidence = 0;
};

class FingerprintService {
 public:
  FingerprintService() : serial_(2), sensor_(&serial_) {}

  void begin();
  void update();
  FingerprintState state() const { return state_; }
  bool takeMatch(FingerprintMatch& result);

 private:
  static constexpr uint32_t RetryIntervalMs = 5000;
  static constexpr uint32_t PollIntervalMs = 250;
  static constexpr uint32_t RemovalPollIntervalMs = 250;
  static constexpr uint32_t ResultHoldMs = 700;

  HardwareSerial serial_;
  Adafruit_Fingerprint sensor_;
  FingerprintState state_ = FingerprintState::Initializing;
  FingerprintMatch pending_match_;
  bool has_pending_match_ = false;
  uint32_t next_poll_ = 0;
  uint32_t next_retry_ = 0;
  uint32_t result_at_ = 0;
  bool removal_required_ = false;

  bool verifyConnection();
  void setState(FingerprintState next);
  void handleReady();
  void handleResultState();
  void handleRemoval();
  bool isCommunicationError(uint8_t result) const;
};

const char* fingerprintStateName(FingerprintState state);
