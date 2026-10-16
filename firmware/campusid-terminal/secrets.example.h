#pragma once

// Copy this file to secrets.h locally. Never commit secrets.h.
#define CAMPUSID_WIFI_SSID "YOUR_WIFI_SSID"
#define CAMPUSID_WIFI_PASSWORD "YOUR_WIFI_PASSWORD"
#define CAMPUSID_HEARTBEAT_URL \
  "https://YOUR_PROJECT.supabase.co/functions/v1/device-heartbeat"
#define CAMPUSID_DEVICE_SECRET "GENERATE_A_LONG_RANDOM_DEVICE_SECRET"

// Provide the CA certificate chain for the HTTPS endpoint. Do not use
// WiFiClientSecure::setInsecure() in production hardware.
#define CAMPUSID_SUPABASE_ROOT_CA "-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----\n"
