#pragma once

#include <Arduino.h>

struct EnrollmentCommand {
  String id;
  String command_type;
  String person_id;
  String display_name;
  uint16_t reserved_slot = 0;
  bool cleanup_only = false;
};

enum class NetworkState {
  Disabled,
  Disconnected,
  Connecting,
  Online,
};

enum class EnrollmentAckResult { Retry, Completed, Failed };

class NetworkService {
 public:
  void begin();
  void updateConnection();
  bool heartbeatDue() const;
  void sendHeartbeat(bool sensor_ready, uint16_t pending_event_count = 0);
  bool commandPollDue() const;
  void pollCommand(uint16_t sensor_capacity);
  NetworkState state() const { return state_; }
  bool online() const { return state_ == NetworkState::Online; }
  bool wifiConnected() const { return wifi_associated_; }
  bool hasPendingEnrollmentCommand() const { return has_pending_command_; }
  bool takeEnrollmentCommand(EnrollmentCommand& command);
  EnrollmentAckResult completeEnrollment(const String& command_id, bool success,
                          uint16_t template_id = 0,
                          const char* error_message = nullptr);

 private:
  static constexpr uint32_t ReconnectIntervalMs = 10000;
  static constexpr uint32_t HeartbeatIntervalMs = 10000;
  static constexpr uint32_t CommandPollIntervalMs = 3000;
  static constexpr uint32_t HttpTimeoutMs = 3000;

  NetworkState state_ = NetworkState::Disabled;
  uint32_t next_reconnect_ = 0;
  uint32_t next_heartbeat_ = 0;
  uint32_t next_command_poll_ = 0;
  uint32_t wifi_begin_at_ = 0;
  int last_wifi_status_ = -1;
  bool wifi_associated_ = false;
  EnrollmentCommand pending_command_;
  bool has_pending_command_ = false;

  bool configured() const;
  void setState(NetworkState next);
  void connect();
  bool sendHeartbeatRequest(bool sensor_ready, uint16_t pending_event_count);
  void pollCommands(uint16_t sensor_capacity);
  bool sendCommandRequest(const String& payload, String& response);
};

const char* networkStateName(NetworkState state);
