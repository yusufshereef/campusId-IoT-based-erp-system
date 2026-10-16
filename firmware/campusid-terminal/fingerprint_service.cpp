#include "fingerprint_service.h"
#include "template_slots.h"

#include <string.h>

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
  return sensor_.getParameters() == FINGERPRINT_OK &&
         sensor_.getTemplateCount() == FINGERPRINT_OK;
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

void FingerprintService::beginEnrollment(const String& display_name,
                                         const uint8_t reserved_slots[128],
                                         bool reservations_valid) {
  if (enrollment_state_ != EnrollmentState::Idle) return;
  enrollment_name_ = display_name;
  enrollment_error_ = "";
  enrollment_template_id_ = 0;
  enrollment_result_pending_ = false;
  enrollment_state_ = EnrollmentState::CaptureFirst;
  enrollment_phase_at_ = millis();
  if (!reservations_valid) {
    failEnrollment("Slot reservations unavailable");
    return;
  }
  memcpy(reserved_slots_, reserved_slots, sizeof(reserved_slots_));
  next_enrollment_poll_ = 0;
  Serial.print("Enrollment started for: ");
  Serial.println(enrollment_name_);
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
        failEnrollment("Finger already exists on sensor");
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
      result = sensor_.image2Tz(2);
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
      enrollment_state_ = EnrollmentState::CheckingStorage;
      return;
    case EnrollmentState::StoringModel: {
      uint16_t slot = 0;
      if (!chooseFreeSlot(slot)) {
        failEnrollment("Fingerprint storage is full");
        return;
      }
      result = sensor_.storeModel(slot);
      if (result != FINGERPRINT_OK) {
        failEnrollment(result == FINGERPRINT_PACKETRECIEVEERR
                           ? "Storage uncertain; inspect sensor"
                           : sensorError(result));
        return;
      }
      enrollment_template_id_ = slot;
      enrollment_result_pending_ = true;
      enrollment_state_ = EnrollmentState::AwaitingAck;
      enrollment_phase_at_ = millis();
      return;
    }
    case EnrollmentState::CheckingStorage:
      if (sensor_.capacity == 0 || sensor_.capacity > 1023) {
        failEnrollment("Sensor capacity unavailable");
        return;
      }
      if (sensor_.getTemplateCount() != FINGERPRINT_OK) {
        failEnrollment("Could not inspect template storage");
        return;
      }
      storage_count_ = sensor_.templateCount;
      storage_capacity_limit_ = sensor_.capacity;
      storage_page_ = 0;
      enrollment_state_ = EnrollmentState::ReadingStorageIndex;
      return;
    case EnrollmentState::ReadingStorageIndex: {
      if (!readTemplateIndex(storage_page_, storage_indexes_[storage_page_])) {
        failEnrollment("Could not verify free storage");
        return;
      }
      const uint16_t page_first = static_cast<uint16_t>(storage_page_) * 256;
      const uint16_t page_last =
          page_first + 255 < storage_capacity_limit_
              ? page_first + 255 : storage_capacity_limit_;
      for (uint16_t occupied = page_first; occupied <= page_last; ++occupied) {
        if (templateSlotOccupied(storage_indexes_[storage_page_], occupied))
          --storage_count_;
      }
      if (storage_page_ < storage_capacity_limit_ / 256) {
        ++storage_page_;
        return;
      }
      if (storage_count_ != 0) {
        failEnrollment("Sensor storage index mismatch");
        return;
      }
      enrollment_state_ = EnrollmentState::StoringModel;
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

bool FingerprintService::readTemplateIndex(uint8_t page, uint8_t index[32]) {
  uint8_t command_data[2] = {0x1F, page};
  Adafruit_Fingerprint_Packet command(FINGERPRINT_COMMANDPACKET, 2, command_data);
  Adafruit_Fingerprint_Packet response(FINGERPRINT_ACKPACKET, 0, command_data);
  sensor_.writeStructuredPacket(command);
  if (sensor_.getStructuredPacket(&response) != FINGERPRINT_OK ||
      response.type != FINGERPRINT_ACKPACKET || response.length != 35 ||
      response.data[0] != FINGERPRINT_OK) return false;
  uint16_t checksum = FINGERPRINT_ACKPACKET + response.length + 2;
  for (uint8_t i = 0; i < 33; ++i) checksum += response.data[i];
  const uint16_t received_checksum =
      (static_cast<uint16_t>(response.data[33]) << 8) | response.data[34];
  if (checksum != received_checksum) return false;
  for (uint8_t i = 0; i < 32; ++i) index[i] = response.data[i + 1];
  return true;
}

bool FingerprintService::chooseFreeSlot(uint16_t& slot) {
  const uint16_t last_slot = storage_capacity_limit_;
  for (uint8_t page = 0; page <= last_slot / 256; ++page) {
    const uint16_t first = page == 0 ? 1 : static_cast<uint16_t>(page) * 256;
    const uint16_t page_end = static_cast<uint16_t>(page) * 256 + 255;
    const uint16_t last = page_end < last_slot ? page_end : last_slot;
    for (uint16_t occupied = first; occupied <= last; ++occupied) {
      const bool sensor_occupied =
          templateSlotOccupied(storage_indexes_[page], occupied);
      const bool database_reserved = templateSlotReserved(reserved_slots_, occupied);
      if (sensor_occupied && !database_reserved) {
        Serial.print("Occupied unmapped template slot: ");
        Serial.println(occupied);
      } else if (!sensor_occupied && database_reserved) {
        Serial.print("Mapped slot missing on sensor: ");
        Serial.println(occupied);
      }
    }
    slot = firstFreeTemplateSlot(storage_indexes_[page], reserved_slots_, first,
                                 last);
    if (slot != 0) return true;
  }
  return false;
}

const char* FingerprintService::sensorError(uint8_t result) const {
  Serial.print("Enrollment sensor code: ");
  Serial.println(result);
  switch (result) {
    case FINGERPRINT_PACKETRECIEVEERR: return "Sensor communication error";
    case FINGERPRINT_IMAGEFAIL:
    case FINGERPRINT_IMAGEMESS:
    case FINGERPRINT_FEATUREFAIL:
    case FINGERPRINT_INVALIDIMAGE: return "Poor image; retry enrollment";
    case FINGERPRINT_ENROLLMISMATCH:
    case FINGERPRINT_NOMATCH: return "Finger mismatch";
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
    case EnrollmentState::CaptureFirst: return "Place finger";
    case EnrollmentState::ConvertFirstCapture:
    case EnrollmentState::CheckExistingTemplate: return "Place finger";
    case EnrollmentState::WaitingForRemoval: return "Remove finger";
    case EnrollmentState::CaptureSecond: return "Place same finger again";
    case EnrollmentState::ConvertSecondCapture: return "Place same finger again";
    case EnrollmentState::CreatingModel:
    case EnrollmentState::CheckingStorage:
    case EnrollmentState::ReadingStorageIndex:
    case EnrollmentState::StoringModel: return "Creating fingerprint";
    case EnrollmentState::AwaitingAck: return "Confirming enrollment";
    case EnrollmentState::Success: return "enrollment complete";
    case EnrollmentState::Failed: return "enrollment failed";
    default: return "unknown";
  }
}
