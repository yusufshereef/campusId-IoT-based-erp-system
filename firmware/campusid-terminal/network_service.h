#pragma once

#include <Arduino.h>

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

 private:
  static constexpr uint32_t ReconnectIntervalMs = 10000;
  static constexpr uint32_t HeartbeatIntervalMs = 15000;
  static constexpr uint32_t HttpTimeoutMs = 3000;

  NetworkState state_ = NetworkState::Disabled;
  uint32_t next_reconnect_ = 0;
  uint32_t next_heartbeat_ = 0;

  bool configured() const;
  void setState(NetworkState next);
  void connect();
  void sendHeartbeat(bool sensor_ready, uint16_t pending_event_count);
};

const char* networkStateName(NetworkState state);
