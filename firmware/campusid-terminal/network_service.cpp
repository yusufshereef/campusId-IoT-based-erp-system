#include "network_service.h"

#include <HTTPClient.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>

#include "hardware_config.h"

#if __has_include("secrets.h")
#include "secrets.h"
#else
#define CAMPUSID_WIFI_SSID ""
#define CAMPUSID_WIFI_PASSWORD ""
#define CAMPUSID_HEARTBEAT_URL ""
#define CAMPUSID_DEVICE_SECRET ""
#define CAMPUSID_SUPABASE_ROOT_CA ""
#endif

namespace {
bool hasValue(const char* value) {
  return value != nullptr && value[0] != '\0';
}
}

void NetworkService::begin() {
  if (!configured()) {
    setState(NetworkState::Disabled);
    return;
  }
  WiFi.mode(WIFI_STA);
  WiFi.setAutoReconnect(true);
  connect();
}

void NetworkService::update(bool sensor_ready, uint16_t pending_event_count) {
  if (!configured()) return;

  if (WiFi.status() != WL_CONNECTED) {
    if (state_ == NetworkState::Online) setState(NetworkState::Disconnected);
    if (static_cast<int32_t>(millis() - next_reconnect_) >= 0) connect();
    return;
  }

  if (state_ != NetworkState::Online) {
    setState(NetworkState::Online);
    next_heartbeat_ = 0;
  }
  if (static_cast<int32_t>(millis() - next_heartbeat_) >= 0) {
    sendHeartbeat(sensor_ready, pending_event_count);
    next_heartbeat_ = millis() + HeartbeatIntervalMs;
  }
}

bool NetworkService::configured() const {
  return hasValue(CAMPUSID_WIFI_SSID) &&
         hasValue(CAMPUSID_WIFI_PASSWORD) &&
         hasValue(CAMPUSID_HEARTBEAT_URL) &&
         hasValue(CAMPUSID_DEVICE_SECRET) &&
         hasValue(CAMPUSID_SUPABASE_ROOT_CA);
}

void NetworkService::setState(NetworkState next) {
  if (state_ == next) return;
  state_ = next;
  Serial.print("Network state: ");
  Serial.println(networkStateName(state_));
}

void NetworkService::connect() {
  WiFi.disconnect();
  WiFi.begin(CAMPUSID_WIFI_SSID, CAMPUSID_WIFI_PASSWORD);
  next_reconnect_ = millis() + ReconnectIntervalMs;
  setState(NetworkState::Connecting);
}

void NetworkService::sendHeartbeat(bool sensor_ready,
                                   uint16_t pending_event_count) {
  WiFiClientSecure client;
  client.setCACert(CAMPUSID_SUPABASE_ROOT_CA);
  HTTPClient request;
  if (!request.begin(client, CAMPUSID_HEARTBEAT_URL)) {
    return;
  }
  request.setTimeout(HttpTimeoutMs);
  request.addHeader("Content-Type", "application/json");
  request.addHeader("X-CampusID-Device-Secret", CAMPUSID_DEVICE_SECRET);
  const String payload =
      "{\"device_id\":\"" CAMPUSID_DEVICE_ID
      "\",\"firmware_version\":\"" CAMPUSID_FIRMWARE_VERSION
      "\",\"sensor_ready\":" +
      String(sensor_ready ? "true" : "false") +
      ",\"pending_event_count\":" + String(pending_event_count) + "}";
  const int status = request.POST(payload);
  request.end();
  if (status < 200 || status >= 300) {
    Serial.print("Heartbeat failed: HTTP ");
    Serial.println(status);
  }
}

const char* networkStateName(NetworkState state) {
  switch (state) {
    case NetworkState::Disabled: return "disabled";
    case NetworkState::Disconnected: return "disconnected";
    case NetworkState::Connecting: return "connecting";
    case NetworkState::Online: return "online";
    default: return "unknown";
  }
}
