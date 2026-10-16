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
#define CAMPUSID_COMMAND_URL ""
#define CAMPUSID_DEVICE_SECRET ""
#define CAMPUSID_SUPABASE_ROOT_CA ""
#endif

#ifndef CAMPUSID_COMMAND_URL
#define CAMPUSID_COMMAND_URL ""
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

  if (static_cast<int32_t>(millis() - next_heartbeat_) >= 0) {
    const bool heartbeat_succeeded =
        sendHeartbeat(sensor_ready, pending_event_count);
    setState(heartbeat_succeeded ? NetworkState::Online
                                 : NetworkState::Disconnected);
    next_heartbeat_ = millis() + HeartbeatIntervalMs;
  }
  if (hasValue(CAMPUSID_COMMAND_URL) &&
      static_cast<int32_t>(millis() - next_command_poll_) >= 0) {
    pollCommands();
    next_command_poll_ = millis() + CommandPollIntervalMs;
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

bool NetworkService::sendHeartbeat(bool sensor_ready,
                                   uint16_t pending_event_count) {
  WiFiClientSecure client;
  client.setCACert(CAMPUSID_SUPABASE_ROOT_CA);
  HTTPClient request;
  if (!request.begin(client, CAMPUSID_HEARTBEAT_URL)) {
    Serial.println("Heartbeat request initialization failed");
    return false;
  }
  request.setTimeout(HttpTimeoutMs);
  request.addHeader("Content-Type", "application/json");
  request.addHeader("X-CampusID-Device-Secret", CAMPUSID_DEVICE_SECRET);
  String payload;
  payload.reserve(128);
  payload += "{\"device_id\":\"";
  payload += CAMPUSID_DEVICE_ID;
  payload += "\",\"firmware_version\":\"";
  payload += CAMPUSID_FIRMWARE_VERSION;
  payload += "\",\"sensor_ready\":";
  payload += sensor_ready ? "true" : "false";
  payload += ",\"pending_event_count\":";
  payload += String(pending_event_count);
  payload += "}";
  const uint32_t heartbeat_started = millis();
  const int status = request.POST(payload);
  const String response_body = request.getString();
  const uint32_t heartbeat_duration = millis() - heartbeat_started;
  request.end();
  Serial.print("Heartbeat: HTTP ");
  Serial.print(status);
  Serial.print(" (");
  Serial.print(heartbeat_duration);
  Serial.println(" ms)");
  if (status < 200 || status >= 300) {
    Serial.print("Heartbeat failed: HTTP ");
    Serial.println(status);
    if (response_body.length() > 0) {
      Serial.print("Heartbeat response: ");
      Serial.println(response_body);
    }
    return false;
  }
  return true;
}

bool NetworkService::takeEnrollmentCommand(EnrollmentCommand& command) {
  if (!has_pending_command_) return false;
  command = pending_command_;
  has_pending_command_ = false;
  return true;
}

bool NetworkService::sendCommandRequest(const String& payload,
                                        String& response) {
  WiFiClientSecure client;
  client.setCACert(CAMPUSID_SUPABASE_ROOT_CA);
  HTTPClient request;
  if (!request.begin(client, CAMPUSID_COMMAND_URL)) return false;
  request.setTimeout(HttpTimeoutMs);
  request.addHeader("Content-Type", "application/json");
  request.addHeader("X-CampusID-Device-Secret", CAMPUSID_DEVICE_SECRET);
  const int status = request.POST(payload);
  response = request.getString();
  request.end();
  return status >= 200 && status < 300;
}

namespace {
String jsonString(const String& source, const char* key) {
  const String marker = String("\"") + key + "\":\"";
  const int start = source.indexOf(marker);
  if (start < 0) return "";
  String value;
  bool escaped = false;
  for (int index = start + marker.length(); index < source.length(); index++) {
    const char character = source[index];
    if (escaped) {
      value += character;
      escaped = false;
    } else if (character == '\\') {
      escaped = true;
    } else if (character == '"') {
      break;
    } else {
      value += character;
    }
  }
  return value;
}
}

void NetworkService::pollCommands() {
  String payload = "{\"device_id\":\"";
  payload += CAMPUSID_DEVICE_ID;
  payload += "\",\"action\":\"poll\"}";
  String response;
  if (!sendCommandRequest(payload, response) ||
      response.indexOf("\"command\":null") >= 0) {
    return;
  }
  EnrollmentCommand command;
  command.id = jsonString(response, "id");
  command.person_id = jsonString(response, "person_id");
  command.display_name = jsonString(response, "display_name");
  if (command.id.length() > 0 && command.person_id.length() > 0) {
    pending_command_ = command;
    has_pending_command_ = true;
  }
}

void NetworkService::completeEnrollment(const String& command_id, bool success,
                                        uint16_t template_id,
                                        const char* error_message) {
  String payload = "{\"device_id\":\"";
  payload += CAMPUSID_DEVICE_ID;
  payload += "\",\"action\":\"complete\",\"command_id\":\"";
  payload += command_id;
  payload += "\",\"success\":";
  payload += (success ? "true" : "false");
  if (success) {
    payload += ",\"template_id\":";
    payload += String(template_id);
  } else if (error_message) {
    payload += ",\"error_message\":\"";
    payload += error_message;
    payload += "\"";
  }
  payload += "}";
  String response;
  if (!sendCommandRequest(payload, response)) {
    Serial.println("Enrollment acknowledgement failed");
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
