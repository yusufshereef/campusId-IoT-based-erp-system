#pragma once
#include "Arduino.h"
#include <cstring>
#include <deque>

constexpr uint8_t FINGERPRINT_OK = 0;
constexpr uint8_t FINGERPRINT_PACKETRECIEVEERR = 1;
constexpr uint8_t FINGERPRINT_NOFINGER = 2;
constexpr uint8_t FINGERPRINT_IMAGEFAIL = 3;
constexpr uint8_t FINGERPRINT_IMAGEMESS = 6;
constexpr uint8_t FINGERPRINT_FEATUREFAIL = 7;
constexpr uint8_t FINGERPRINT_NOMATCH = 8;
constexpr uint8_t FINGERPRINT_NOTFOUND = 9;
constexpr uint8_t FINGERPRINT_ENROLLMISMATCH = 10;
constexpr uint8_t FINGERPRINT_BADLOCATION = 11;
constexpr uint8_t FINGERPRINT_INVALIDIMAGE = 21;
constexpr uint8_t FINGERPRINT_FLASHERR = 24;
constexpr uint8_t FINGERPRINT_COMMANDPACKET = 1;
constexpr uint8_t FINGERPRINT_ACKPACKET = 7;

struct Adafruit_Fingerprint_Packet {
  uint8_t type;
  uint16_t length;
  uint8_t data[64] = {};
  Adafruit_Fingerprint_Packet(uint8_t t, uint16_t n, uint8_t* p)
      : type(t), length(n) { std::memcpy(data, p, n); }
};

struct SensorFixture {
  std::deque<uint8_t> images;
  uint8_t occupied[128] = {};
  uint8_t search = FINGERPRINT_NOTFOUND;
  uint8_t conversion = FINGERPRINT_OK;
  uint8_t create = FINGERPRINT_OK;
  uint8_t store = FINGERPRINT_OK;
  bool index_available = true;
  bool corrupt_checksum = false;
  unsigned stores = 0;
  uint16_t stored_slot = 0;
};
inline SensorFixture sensor_fixture;

class Adafruit_Fingerprint {
 public:
  explicit Adafruit_Fingerprint(HardwareSerial*) {}
  uint16_t capacity = 64;
  uint16_t templateCount = 0;
  uint16_t fingerID = 1;
  uint16_t confidence = 100;
  void begin(uint32_t) {}
  bool verifyPassword() { return true; }
  uint8_t getParameters() { return FINGERPRINT_OK; }
  uint8_t getTemplateCount() {
    templateCount = 0;
    for (unsigned slot = 0; slot < capacity; ++slot)
      if (sensor_fixture.occupied[slot / 8] & (1u << (slot % 8))) ++templateCount;
    return FINGERPRINT_OK;
  }
  uint8_t getImage() {
    if (sensor_fixture.images.empty()) return FINGERPRINT_NOFINGER;
    const auto next = sensor_fixture.images.front();
    sensor_fixture.images.pop_front();
    return next;
  }
  uint8_t image2Tz(uint8_t = 1) { return sensor_fixture.conversion; }
  uint8_t fingerSearch(uint8_t = 1) { return sensor_fixture.search; }
  uint8_t fingerFastSearch() { return sensor_fixture.search; }
  uint8_t createModel() { return sensor_fixture.create; }
  uint8_t storeModel(uint16_t slot) {
    ++sensor_fixture.stores;
    sensor_fixture.stored_slot = slot;
    if (sensor_fixture.store == FINGERPRINT_OK)
      sensor_fixture.occupied[slot / 8] |= 1u << (slot % 8);
    return sensor_fixture.store;
  }
  void writeStructuredPacket(const Adafruit_Fingerprint_Packet& packet) {
    page_ = packet.data[1];
  }
  uint8_t getStructuredPacket(Adafruit_Fingerprint_Packet* packet) {
    if (!sensor_fixture.index_available) return FINGERPRINT_PACKETRECIEVEERR;
    packet->type = FINGERPRINT_ACKPACKET;
    packet->length = 35;
    packet->data[0] = FINGERPRINT_OK;
    std::memcpy(packet->data + 1, sensor_fixture.occupied + page_ * 32, 32);
    uint16_t checksum = 7 + 35 + 2;
    for (unsigned i = 0; i < 33; ++i) checksum += packet->data[i];
    packet->data[33] = checksum >> 8;
    packet->data[34] = checksum & 255;
    if (sensor_fixture.corrupt_checksum) packet->data[34] ^= 1;
    return FINGERPRINT_OK;
  }
 private:
  uint8_t page_ = 0;
};
