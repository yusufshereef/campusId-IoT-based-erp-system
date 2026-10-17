#include "fingerprint_service.h"
namespace {
constexpr uint32_t SensorBaud = 57600;
}

void FingerprintService::begin() {
  setState(FingerprintState::Initializing);
  serial_.begin(SensorBaud, SERIAL_8N1, CampusIdPins::R307Rx,
                CampusIdPins::R307Tx);
  sensor_.begin(SensorBaud);

  if (verifyConnection()) {
    setState(FingerprintState::Ready);
  } else {
    next_retry_ = millis() + RetryIntervalMs;
    setState(FingerprintState::SensorUnavailable);
  }
}

bool FingerprintService::verifyConnection() {
  if (!sensor_.verifyPassword()) {
    return false;
  }
  if (sensor_.getParameters() != FINGERPRINT_OK) return false;
  Serial.print("Fingerprint capacity: ");
  Serial.println(sensor_.capacity);
  if (sensor_.capacity == 0 || sensor_.capacity > 1023) {
    Serial.println("Fingerprint capacity invalid");
    return false;
  }
  if (sensor_.getTemplateCount() != FINGERPRINT_OK) {
    Serial.println("Fingerprint template count unavailable");
    return false;
  }
  Serial.print("Fingerprint templates before reset: ");
  Serial.println(sensor_.templateCount);
  return true;
}

void FingerprintService::update() {
  const uint32_t now = millis();
  if (enrollment_state_ != EnrollmentState::Idle) {
    updateEnrollment();
    return;
  }
  if (state_ == FingerprintState::SensorUnavailable ||
      state_ == FingerprintState::CommunicationError) {
    if (static_cast<int32_t>(now - next_retry_) < 0) return;
    if (verifyConnection()) {
      setState(removal_required_ ? FingerprintState::WaitingForRemoval
                                 : FingerprintState::Ready);
    } else {
      next_retry_ = now + RetryIntervalMs;
      setState(FingerprintState::SensorUnavailable);
    }
    return;
  }
  if (static_cast<int32_t>(now - next_poll_) < 0) return;

  if (state_ == FingerprintState::Ready) {
    next_poll_ = now + PollIntervalMs;
    handleReady();
  } else if (state_ == FingerprintState::Matched ||
             state_ == FingerprintState::NoMatch) {
    handleResultState();
  } else if (state_ == FingerprintState::WaitingForRemoval) {
    next_poll_ = now + RemovalPollIntervalMs;
    handleRemoval();
  }
}

bool FingerprintService::beginEnrollment(const String& display_name,
                                         uint16_t reserved_slot) {
  if (enrollment_state_ != EnrollmentState::Idle) return false;
  enrollment_name_ = display_name;
  enrollment_error_ = "";
  enrollment_template_id_ = 0;
  enrollment_result_pending_ = false;
  reserved_slot_ = reserved_slot;
  enrollment_state_ = EnrollmentState::PreparingEnrollment;
  enrollment_phase_at_ = millis();
  if (reserved_slot_ == 0 || reserved_slot_ > sensor_.capacity) {
    failEnrollment("Fingerprint storage full");
    return false;
  }
  next_enrollment_poll_ = 0;
  Serial.print("Enrollment prepared for slot: ");
  Serial.println(reserved_slot_);
  return true;
}

bool FingerprintService::deleteTemplate(uint16_t slot_id, String& error_message) {
  error_message = "";
  if (state_ != FingerprintState::Ready || enrollment_state_ != EnrollmentState::Idle) {
    error_message = "Terminal busy; fingerprint retained";
    return false;
  }
  if (slot_id == 0 || slot_id > sensor_.capacity) {
    error_message = "Invalid fingerprint slot; fingerprint retained";
    return false;
  }
  // A retry is bound to the backend-authoritative slot. If recovery proves
  // that exact slot is already empty, converge without issuing another delete.
  bool presence_known = false;
  const bool present = templatePresent(slot_id, presence_known);
  if (presence_known && !present) {
    removal_required_ = true;
    setState(FingerprintState::WaitingForRemoval);
    return true;
  }
  // If loadModel cannot establish presence, deleteModel still targets this
  // exact validated slot. Its response determines whether cleanup converged.
  // This is the only deleteModel call for a claimed command. The caller retains
  // the result and retries only the backend acknowledgement.
  const uint8_t result = sensor_.deleteModel(slot_id);
  if (result != FINGERPRINT_OK) {
    if (result == FINGERPRINT_BADLOCATION) {
      // The requested slot has already been validated against sensor capacity;
      // BADLOCATION here means that exact target is now absent.
      removal_required_ = true;
      setState(FingerprintState::WaitingForRemoval);
      return true;
    }
    if (result == FINGERPRINT_PACKETRECIEVEERR)
      error_message = "Sensor communication error; deletion outcome uncertain";
    else if (result == FINGERPRINT_FLASHERR)
      error_message = "Sensor flash error; inspect terminal";
    else if (result == FINGERPRINT_BADLOCATION)
      error_message = "Target slot could not be verified; inspect terminal";
    else
      error_message = "Sensor rejected deletion; fingerprint retained";
    return false;
  }
  removal_required_ = true;
  setState(FingerprintState::WaitingForRemoval);
  return true;
}

bool FingerprintService::templatePresent(uint16_t slot_id, bool& known) {
  known = false;
  if (state_ != FingerprintState::Ready || slot_id == 0 || slot_id > sensor_.capacity)
    return false;
  const uint8_t result = sensor_.loadModel(slot_id);
  if (result == FINGERPRINT_OK) {
    known = true;
    return true;
  }
  // loadModel reports BADLOCATION for an unavailable page; NOTFOUND is the
  // matching-search result and is not evidence that a template slot is empty.
  // Bounds above ensure this is the exact in-capacity slot from the command.
  if (result == FINGERPRINT_BADLOCATION) {
    known = true;
    return false;
  }
  return false;
}

bool FingerprintService::resetFingerprintDatabase() {
  Serial.println("Fingerprint reset requested");
  if (state_ != FingerprintState::Ready || enrollment_state_ != EnrollmentState::Idle) {
    Serial.println("Fingerprint reset refused; terminal busy");
    return false;
  }
  if (sensor_.emptyDatabase() != FINGERPRINT_OK) {
    Serial.println("Fingerprint reset failed");
    return false;
  }
  if (sensor_.getTemplateCount() != FINGERPRINT_OK || sensor_.templateCount != 0) {
    Serial.println("Fingerprint reset verification failed");
    return false;
  }
  Serial.println("Fingerprint database cleared");
  Serial.print("Templates after reset: ");
  Serial.println(sensor_.templateCount);
  return true;
}

void FingerprintService::updateEnrollment() {
  const uint32_t now = millis();
  if (enrollment_state_ == EnrollmentState::Success ||
      enrollment_state_ == EnrollmentState::Failed) {
    if (now - enrollment_result_at_ >= EnrollmentResultHoldMs) {
      enrollment_state_ = EnrollmentState::Idle;
      // Require removal after enrollment before recognizing the same finger.
      removal_required_ = true;
      setState(FingerprintState::WaitingForRemoval);
    }
    return;
  }
  if (enrollment_state_ == EnrollmentState::AwaitingAck) {
    if (now - enrollment_phase_at_ >= AckScreenTimeoutMs) {
      // The main-loop ACK record remains intact. Resume local recognition
      // after the result hold, while only that same ACK continues retrying.
      if (enrollment_error_.length() == 0)
        enrollment_error_ = "Confirmation pending; retrying";
      enrollment_state_ = EnrollmentState::Failed;
      enrollment_result_at_ = now;
    }
    return;
  }
  const uint32_t phase_timeout =
      enrollment_state_ == EnrollmentState::PreparingEnrollment ? PreparingTimeoutMs :
      enrollment_state_ == EnrollmentState::CaptureFirst ? FirstFingerTimeoutMs :
      enrollment_state_ == EnrollmentState::WaitingForRemoval ? RemovalTimeoutMs :
      enrollment_state_ == EnrollmentState::CaptureSecond ? SecondFingerTimeoutMs : 0;
  if (phase_timeout && now - enrollment_phase_at_ >= phase_timeout) {
    failEnrollment("Enrollment timed out");
    return;
  }
  if (static_cast<int32_t>(now - next_enrollment_poll_) < 0) return;
  next_enrollment_poll_ = now + EnrollmentPollIntervalMs;
  uint8_t result;
  switch (enrollment_state_) {
    case EnrollmentState::PreparingEnrollment:
      if (reserved_slot_ == 0 || reserved_slot_ > sensor_.capacity) {
        failEnrollment("Fingerprint storage full");
        return;
      }
      enrollment_state_ = EnrollmentState::CaptureFirst;
      enrollment_phase_at_ = now;
      return;
    case EnrollmentState::CaptureFirst:
      result = sensor_.getImage();
      if (result == FINGERPRINT_NOFINGER) return;
      if (result != FINGERPRINT_OK) {
        failEnrollment(sensorError(result));
        return;
      }
      enrollment_state_ = EnrollmentState::ConvertFirstCapture;
      return;
    case EnrollmentState::ConvertFirstCapture:
      result = sensor_.image2Tz(1);
      if (result != FINGERPRINT_OK) {
        failEnrollment(sensorError(result));
        return;
      }
      enrollment_state_ = EnrollmentState::CheckExistingTemplate;
      return;
    case EnrollmentState::CheckExistingTemplate:
      result = sensor_.fingerSearch(1);
      if (result == FINGERPRINT_OK) {
        failEnrollment("Fingerprint already enrolled");
        return;
      }
      if (result != FINGERPRINT_NOTFOUND) {
        failEnrollment(sensorError(result));
        return;
      }
      enrollment_state_ = EnrollmentState::WaitingForRemoval;
      enrollment_phase_at_ = millis();
      return;
    case EnrollmentState::WaitingForRemoval:
      result = sensor_.getImage();
      if (result == FINGERPRINT_NOFINGER) {
        enrollment_state_ = EnrollmentState::CaptureSecond;
        enrollment_phase_at_ = millis();
      } else if (result == FINGERPRINT_PACKETRECIEVEERR) {
        failEnrollment("Sensor communication error");
      }
      return;
    case EnrollmentState::CaptureSecond:
      result = sensor_.getImage();
      if (result == FINGERPRINT_NOFINGER) return;
      if (result != FINGERPRINT_OK) {
        failEnrollment(sensorError(result));
        return;
      }
      enrollment_state_ = EnrollmentState::ConvertSecondCapture;
      return;
    case EnrollmentState::ConvertSecondCapture:
      result = sensor_.image2Tz(2);
      if (result != FINGERPRINT_OK) {
        failEnrollment(sensorError(result));
        return;
      }
      enrollment_state_ = EnrollmentState::CreatingModel;
      return;
    case EnrollmentState::CreatingModel:
      result = sensor_.createModel();
      if (result != FINGERPRINT_OK) {
        failEnrollment(sensorError(result));
        return;
      }
      enrollment_state_ = EnrollmentState::StoringModel;
      return;
    case EnrollmentState::StoringModel: {
      if (reserved_slot_ == 0 || reserved_slot_ > sensor_.capacity) {
        failEnrollment("Fingerprint storage full");
        return;
      }
      result = sensor_.storeModel(reserved_slot_);
      if (result != FINGERPRINT_OK) {
        failEnrollment(result == FINGERPRINT_PACKETRECIEVEERR
                           ? "Storage uncertain; inspect sensor"
                           : sensorError(result));
        return;
      }
      enrollment_template_id_ = reserved_slot_;
      enrollment_result_pending_ = true;
      enrollment_state_ = EnrollmentState::AwaitingAck;
      enrollment_phase_at_ = millis();
      return;
    }
    default:
      return;
  }
}

void FingerprintService::failEnrollment(const char* message) {
  enrollment_error_ = message;
  enrollment_result_pending_ = true;
  enrollment_state_ = EnrollmentState::AwaitingAck;
  enrollment_phase_at_ = millis();
  Serial.print("Enrollment failed: ");
  Serial.println(message);
}

bool FingerprintService::takeEnrollmentResult(bool& success,
                                              uint16_t& template_id,
                                              String& error_message) {
  if (!enrollment_result_pending_) return false;
  enrollment_result_pending_ = false;
  success = enrollment_template_id_ != 0 && enrollment_error_.length() == 0;
  template_id = enrollment_template_id_;
  error_message = enrollment_error_;
  return true;
}

void FingerprintService::enrollmentAcknowledged(bool accepted) {
  if (!accepted && enrollment_error_.length() == 0)
    enrollment_error_ = "Backend rejected; inspect sensor";
  enrollment_result_at_ = millis();
  enrollment_state_ = accepted && enrollment_template_id_ != 0
                          ? EnrollmentState::Success : EnrollmentState::Failed;
  if (enrollment_state_ == EnrollmentState::Success) enrollment_error_ = "";
}

const char* FingerprintService::sensorError(uint8_t result) const {
  Serial.print("Enrollment sensor code: ");
  Serial.println(result);
  switch (result) {
    case FINGERPRINT_PACKETRECIEVEERR: return "Sensor communication error";
    case FINGERPRINT_IMAGEFAIL: return "Image capture error";
    case FINGERPRINT_IMAGEMESS: return "Poor image; try again";
    case FINGERPRINT_FEATUREFAIL:
    case FINGERPRINT_INVALIDIMAGE: return "Feature extraction error";
    case FINGERPRINT_ENROLLMISMATCH:
    case FINGERPRINT_NOMATCH: return "Fingerprints did not match; try again";
    case FINGERPRINT_BADLOCATION: return "Sensor slot unavailable";
    case FINGERPRINT_FLASHERR: return "Sensor storage error";
    default: return "Sensor error";
  }
}

void FingerprintService::handleReady() {
  const uint8_t result = sensor_.getImage();
  if (result == FINGERPRINT_NOFINGER) {
    return;
  }
  if (isCommunicationError(result)) {
    next_retry_ = millis() + RetryIntervalMs;
    setState(FingerprintState::CommunicationError);
    return;
  }
  removal_required_ = true;
  setState(FingerprintState::Scanning);
  if (result != FINGERPRINT_OK) {
    setState(FingerprintState::NoMatch);
    result_at_ = millis();
    return;
  }

  const uint8_t conversion = sensor_.image2Tz();
  if (conversion != FINGERPRINT_OK) {
    if (isCommunicationError(conversion)) {
      next_retry_ = millis() + RetryIntervalMs;
      setState(FingerprintState::CommunicationError);
    } else {
      result_at_ = millis();
      setState(FingerprintState::NoMatch);
    }
    return;
  }

  const uint8_t search = sensor_.fingerFastSearch();
  if (search == FINGERPRINT_OK) {
    pending_match_.template_id = sensor_.fingerID;
    pending_match_.confidence = sensor_.confidence;
    has_pending_match_ = true;
    result_at_ = millis();
    setState(FingerprintState::Matched);
  } else if (search == FINGERPRINT_NOTFOUND) {
    result_at_ = millis();
    setState(FingerprintState::NoMatch);
  } else {
    next_retry_ = millis() + RetryIntervalMs;
    setState(FingerprintState::CommunicationError);
  }
}

void FingerprintService::handleResultState() {
  if (millis() - result_at_ >= ResultHoldMs) {
    setState(FingerprintState::WaitingForRemoval);
    next_poll_ = millis();
  }
}

void FingerprintService::handleRemoval() {
  const uint8_t result = sensor_.getImage();
  if (result == FINGERPRINT_NOFINGER) {
    removal_required_ = false;
    setState(FingerprintState::Ready);
    return;
  }
  if (isCommunicationError(result)) {
    next_retry_ = millis() + RetryIntervalMs;
    setState(FingerprintState::CommunicationError);
  }
}

bool FingerprintService::isCommunicationError(uint8_t result) const {
  // Poor images require removal and retry, not a disconnected-sensor warning.
  return result == FINGERPRINT_PACKETRECIEVEERR;
}

void FingerprintService::setState(FingerprintState next) {
  if (state_ == next) return;
  state_ = next;
}

bool FingerprintService::takeMatch(FingerprintMatch& result) {
  if (!has_pending_match_) return false;
  result = pending_match_;
  has_pending_match_ = false;
  return true;
}

const char* fingerprintStateName(FingerprintState state) {
  switch (state) {
    case FingerprintState::Initializing: return "initializing";
    case FingerprintState::Ready: return "ready";
    case FingerprintState::SensorUnavailable: return "sensor unavailable";
    case FingerprintState::Scanning: return "scanning";
    case FingerprintState::Matched: return "matched";
    case FingerprintState::NoMatch: return "no match";
    case FingerprintState::CommunicationError: return "communication error";
    case FingerprintState::WaitingForRemoval: return "waiting for finger removal";
    default: return "unknown";
  }
}

const char* enrollmentStateName(EnrollmentState state) {
  switch (state) {
    case EnrollmentState::Idle: return "idle";
    case EnrollmentState::PreparingEnrollment: return "Preparing enrollment";
    case EnrollmentState::CaptureFirst: return "Place finger";
    case EnrollmentState::ConvertFirstCapture:
    case EnrollmentState::CheckExistingTemplate: return "Place finger";
    case EnrollmentState::WaitingForRemoval: return "Remove finger";
    case EnrollmentState::CaptureSecond: return "Place same finger again";
    case EnrollmentState::ConvertSecondCapture: return "Place same finger again";
    case EnrollmentState::CreatingModel:
    case EnrollmentState::StoringModel: return "Creating fingerprint";
    case EnrollmentState::AwaitingAck: return "Saving enrollment";
    case EnrollmentState::Success: return "enrollment complete";
    case EnrollmentState::Failed: return "enrollment failed";
    default: return "unknown";
  }
}
