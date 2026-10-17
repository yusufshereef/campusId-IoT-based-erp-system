#include "network_service.h"

#include <HTTPClient.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>

#include "hardware_config.h"

#if __has_include("secrets.h")
#include "secrets.h"
#define CAMPUSID_SECRETS_HEADER_FOUND 1
#else
#define CAMPUSID_SECRETS_HEADER_FOUND 0
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

const char* wifiStatusName(int status) {
  switch (status) {
    case WL_IDLE_STATUS: return "idle";
    case WL_NO_SSID_AVAIL: return "no ssid";
    case WL_SCAN_COMPLETED: return "scan complete";
    case WL_CONNECTED: return "connected";
    case WL_CONNECT_FAILED: return "connect failed";
    case WL_CONNECTION_LOST: return "connection lost";
    case WL_DISCONNECTED: return "disconnected";
    default: return "unknown";
  }
}

void logWifiStatus(int status) {
  Serial.print("WiFi status: ");
  Serial.print(status);
  Serial.print(" (");
  Serial.print(wifiStatusName(status));
  Serial.println(")");
}
}

void NetworkService::begin() {
  Serial.println("Network service begin");
#if CAMPUSID_SECRETS_HEADER_FOUND
  Serial.println("Network config: present");
#else
  Serial.println("Network config: missing");
#endif
  const bool network_configured = configured();
  Serial.print("Network configured(): ");
  Serial.println(network_configured ? "true" : "false");
  if (!network_configured) {
    setState(NetworkState::Disabled);
    return;
  }
  WiFi.mode(WIFI_STA);
  WiFi.setAutoReconnect(true);
  connect();
}

void NetworkService::updateConnection() {
  if (!configured()) return;

  const int wifi_status = WiFi.status();
  if (wifi_status != last_wifi_status_) {
    last_wifi_status_ = wifi_status;
    logWifiStatus(wifi_status);
  }

  if (wifi_status != WL_CONNECTED) {
    wifi_associated_ = false;
    if (state_ == NetworkState::Online) setState(NetworkState::Disconnected);
    if (static_cast<int32_t>(millis() - next_reconnect_) >= 0) connect();
    return;
  }

  if (!wifi_associated_) {
    wifi_associated_ = true;
    WiFi.setSleep(false);
    Serial.print("WiFi associated in ");
    Serial.print(millis() - wifi_begin_at_);
    Serial.println(" ms");
  }

}

bool NetworkService::heartbeatDue() const {
  return wifi_associated_ &&
         static_cast<int32_t>(millis() - next_heartbeat_) >= 0;
}

void NetworkService::sendHeartbeat(bool sensor_ready,
                                   uint16_t pending_event_count) {
  Serial.println("Heartbeat starting");
  const bool succeeded = sendHeartbeatRequest(sensor_ready, pending_event_count);
  setState(succeeded ? NetworkState::Online : NetworkState::Disconnected);
  next_heartbeat_ = millis() + HeartbeatIntervalMs;
}

bool NetworkService::commandPollDue() const {
  return wifi_associated_ && hasValue(CAMPUSID_COMMAND_URL) &&
         static_cast<int32_t>(millis() - next_command_poll_) >= 0;
}

void NetworkService::pollCommand(uint16_t sensor_capacity) {
  pollCommands(sensor_capacity);
  next_command_poll_ = millis() + CommandPollIntervalMs;
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
  const uint32_t now = millis();
  // Do not abort the first association with disconnect()+begin(). That race
  // left the radio in CONNECTING forever when the loop was also busy painting.
  if (state_ == NetworkState::Connecting ||
      state_ == NetworkState::Disconnected) {
    WiFi.disconnect();
  }
  logWifiStatus(WiFi.status());
  Serial.println("WiFi.begin() called");
  WiFi.begin(CAMPUSID_WIFI_SSID, CAMPUSID_WIFI_PASSWORD);
  wifi_begin_at_ = now;
  wifi_associated_ = false;
  next_reconnect_ = now + ReconnectIntervalMs;
  setState(NetworkState::Connecting);
}

bool NetworkService::sendHeartbeatRequest(bool sensor_ready,
                                         uint16_t pending_event_count) {
  WiFiClientSecure client;
  client.setCACert(CAMPUSID_SUPABASE_ROOT_CA);
  HTTPClient request;
  const bool request_ready = request.begin(client, CAMPUSID_HEARTBEAT_URL);
  Serial.print("Heartbeat HTTP begin: ");
  Serial.println(request_ready ? "ok" : "failed");
  if (!request_ready) {
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
  if (status < 0) {
    Serial.print("Heartbeat transport error: ");
    Serial.println(request.errorToString(status));
    char tls_error[128] = {};
    const int tls_code = client.lastError(tls_error, sizeof(tls_error));
    if (tls_code != 0) {
      Serial.print("Heartbeat TLS error ");
      Serial.print(tls_code);
      Serial.print(": ");
      Serial.println(tls_error);
    }
  }
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
  Serial.print("Device command HTTP: ");
  Serial.println(status);
  if (status < 0) Serial.println(request.errorToString(status));
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

uint16_t jsonNumber(const String& source, const char* key) {
  const String marker = String("\"") + key + "\":";
  const int start = source.indexOf(marker);
  if (start < 0) return 0;
  int position = start + marker.length();
  while (position < source.length() && source[position] == ' ') ++position;
  if (position >= source.length() || source[position] < '0' ||
      source[position] > '9') return 0;
  uint32_t value = 0;
  do {
    value = value * 10 + (source[position] - '0');
    if (value > 1023) return 0;
    ++position;
  } while (position < source.length() && source[position] >= '0' &&
           source[position] <= '9');
  return static_cast<uint16_t>(value);
}

bool jsonBool(const String& source, const char* key) {
  const String marker = String("\"") + key + "\":";
  const int start = source.indexOf(marker);
  if (start < 0) return false;
  int position = start + marker.length();
  while (position < source.length() && source[position] == ' ') ++position;
  return source.substring(position, position + 4) == "true";
}
}

void NetworkService::pollCommands(uint16_t sensor_capacity) {
  String payload = "{\"device_id\":\"";
  payload += CAMPUSID_DEVICE_ID;
  payload += "\",\"action\":\"poll\",\"sensor_capacity\":";
  payload += String(sensor_capacity);
  payload += "}";
  String response;
  if (!sendCommandRequest(payload, response) ||
      response.indexOf("\"command\":null") >= 0) {
    return;
  }
  EnrollmentCommand command;
  command.id = jsonString(response, "id");
  command.command_type = jsonString(response, "command_type");
  command.person_id = jsonString(response, "person_id");
  command.display_name = jsonString(response, "display_name");
  command.reserved_slot = jsonNumber(response, "reserved_slot");
  command.cleanup_only = jsonBool(response, "cleanup_only");
  const bool identifiers_valid = command.cleanup_only || command.person_id.length() > 0;
  if (command.id.length() > 0 && identifiers_valid &&
      command.reserved_slot > 0 &&
      (command.command_type == "ENROLL_FINGERPRINT" ||
       command.command_type == "DELETE_FINGERPRINT")) {
    pending_command_ = command;
    has_pending_command_ = true;
  }
}

EnrollmentAckResult NetworkService::completeEnrollment(const String& command_id, bool success,
                                        uint16_t template_id,
                                        const char* error_message) {
  String payload = "{\"device_id\":\"";
  payload += CAMPUSID_DEVICE_ID;
  payload += "\",\"action\":\"complete\",\"command_id\":\"";
  payload += command_id;
  payload += "\",\"success\":";
  payload += (success ? "true" : "false");
  if (template_id > 0) {
    payload += ",\"template_id\":";
    payload += String(template_id);
  }
  if (!success && error_message) {
    payload += ",\"error_message\":\"";
    payload += error_message;
    payload += "\"";
  }
  payload += "}";
  String response;
  if (!sendCommandRequest(payload, response)) {
    Serial.println("Enrollment acknowledgement failed");
    return EnrollmentAckResult::Retry;
  }
  if (response.indexOf("\"status\":\"completed\"") >= 0)
    return EnrollmentAckResult::Completed;
  if (response.indexOf("\"status\":\"failed\"") >= 0 ||
      response.indexOf("\"status\":\"cancelled\"") >= 0 ||
      response.indexOf("\"status\":\"rejected\"") >= 0)
    return EnrollmentAckResult::Failed;
  return EnrollmentAckResult::Retry;
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
