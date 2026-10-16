#pragma once

#include <Arduino.h>

struct EnrollmentCommand {
  String id;
  String person_id;
  String display_name;
};

enum class NetworkState {
  Disabled,
  Disconnected,
  Connecting,
  Online,
};

class NetworkService {
 public:
  void begin();
  void update(bool sensor_ready, uint16_t pending_event_count = 0);
  NetworkState state() const { return state_; }
  bool online() const { return state_ == NetworkState::Online; }
  bool takeEnrollmentCommand(EnrollmentCommand& command);
  void completeEnrollment(const String& command_id, bool success,
                          uint16_t template_id = 0,
                          const char* error_message = nullptr);

 private:
  static constexpr uint32_t ReconnectIntervalMs = 10000;
  static constexpr uint32_t HeartbeatIntervalMs = 5000;
  static constexpr uint32_t CommandPollIntervalMs = 1000;
  static constexpr uint32_t HttpTimeoutMs = 3000;

  NetworkState state_ = NetworkState::Disabled;
  uint32_t next_reconnect_ = 0;
  uint32_t next_heartbeat_ = 0;
  uint32_t next_command_poll_ = 0;
  EnrollmentCommand pending_command_;
  bool has_pending_command_ = false;

  bool configured() const;
  void setState(NetworkState next);
  void connect();
  bool sendHeartbeat(bool sensor_ready, uint16_t pending_event_count);
  void pollCommands();
  bool sendCommandRequest(const String& payload, String& response);
};

const char* networkStateName(NetworkState state);
