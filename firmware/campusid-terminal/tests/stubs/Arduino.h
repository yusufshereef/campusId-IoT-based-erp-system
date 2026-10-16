#pragma once
#include <stdint.h>
#include <string>

inline uint32_t test_millis = 0;
inline uint32_t millis() { return test_millis; }
constexpr int SERIAL_8N1 = 0;
class String {
 public:
  String(const char* text = "") : text_(text) {}
  unsigned int length() const { return text_.length(); }
  const char* c_str() const { return text_.c_str(); }
 private:
  std::string text_;
};
struct HardwareSerial {
  explicit HardwareSerial(int) {}
  void begin(uint32_t, int, int, int) {}
};
struct TestSerial {
  template <typename T> void print(const T&) {}
  template <typename T> void println(const T&) {}
};
inline TestSerial Serial;
