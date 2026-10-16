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
  return sensor_.getTemplateCount() == FINGERPRINT_OK;
}

void FingerprintService::update() {
  const uint32_t now = millis();
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
