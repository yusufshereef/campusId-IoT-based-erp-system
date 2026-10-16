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

enum class EnrollmentState {
  Idle,
  CaptureFirst,
  ConvertFirstCapture,
  CheckExistingTemplate,
  WaitingForRemoval,
  CaptureSecond,
  ConvertSecondCapture,
  CreatingModel,
  CheckingStorage,
  ReadingStorageIndex,
  StoringModel,
  AwaitingAck,
  Success,
  Failed,
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
  void beginEnrollment(const String& display_name,
                       const uint8_t reserved_slots[128],
                       bool reservations_valid);
  EnrollmentState enrollmentState() const { return enrollment_state_; }
  const String& enrollmentName() const { return enrollment_name_; }
  bool enrollmentActive() const {
    return enrollment_state_ != EnrollmentState::Idle &&
           enrollment_state_ != EnrollmentState::Success &&
           enrollment_state_ != EnrollmentState::Failed;
  }
  bool takeEnrollmentResult(bool& success, uint16_t& template_id,
                            String& error_message);
  void enrollmentAcknowledged(bool accepted);
  uint16_t enrollmentTemplateId() const { return enrollment_template_id_; }
  const String& enrollmentError() const { return enrollment_error_; }

 private:
  static constexpr uint32_t RetryIntervalMs = 5000;
  static constexpr uint32_t PollIntervalMs = 250;
  static constexpr uint32_t RemovalPollIntervalMs = 250;
  static constexpr uint32_t ResultHoldMs = 700;
  static constexpr uint32_t EnrollmentPollIntervalMs = 250;
  static constexpr uint32_t EnrollmentResultHoldMs = 4000;
  static constexpr uint32_t FirstFingerTimeoutMs = 60000;
  static constexpr uint32_t RemovalTimeoutMs = 20000;
  static constexpr uint32_t SecondFingerTimeoutMs = 60000;
  static constexpr uint32_t AckScreenTimeoutMs = 30000;

  HardwareSerial serial_;
  Adafruit_Fingerprint sensor_;
  FingerprintState state_ = FingerprintState::Initializing;
  FingerprintMatch pending_match_;
  bool has_pending_match_ = false;
  uint32_t next_poll_ = 0;
  uint32_t next_retry_ = 0;
  uint32_t result_at_ = 0;
  bool removal_required_ = false;
  EnrollmentState enrollment_state_ = EnrollmentState::Idle;
  String enrollment_name_;
  uint32_t next_enrollment_poll_ = 0;
  uint32_t enrollment_result_at_ = 0;
  uint32_t enrollment_phase_at_ = 0;
  uint16_t enrollment_template_id_ = 0;
  String enrollment_error_;
  bool enrollment_result_pending_ = false;
  uint8_t reserved_slots_[128] = {};
  uint8_t storage_indexes_[4][32] = {};
  uint8_t storage_page_ = 0;
  uint16_t storage_count_ = 0;
  uint16_t storage_capacity_limit_ = 0;

  bool verifyConnection();
  void setState(FingerprintState next);
  void handleReady();
  void handleResultState();
  void handleRemoval();
  bool isCommunicationError(uint8_t result) const;
  void updateEnrollment();
  void failEnrollment(const char* message);
  bool chooseFreeSlot(uint16_t& slot);
  bool readTemplateIndex(uint8_t page, uint8_t index[32]);
  const char* sensorError(uint8_t result) const;
};

const char* fingerprintStateName(FingerprintState state);
const char* enrollmentStateName(EnrollmentState state);
