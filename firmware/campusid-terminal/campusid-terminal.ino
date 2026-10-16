#include "display_adapter.h"
#include "fingerprint_service.h"
#include "hardware_config.h"
#include "hardware_self_test.h"
#include "keypad_input.h"
#include "network_service.h"
#include "status_feedback.h"

DisplayAdapter display;
KeypadInput keypad;
StatusFeedback feedback;
HardwareSelfTest self_test;
FingerprintService fingerprint;
NetworkService network;

enum class Screen { Home, Menu, HardwareTest, DeviceStatus, About };
Screen screen = Screen::Home;
uint8_t menu_index = 0;
FingerprintState last_fingerprint_state = FingerprintState::Initializing;
uint32_t last_fingerprint_diagnostic = 0;
bool has_fingerprint_diagnostic = false;
constexpr uint32_t FingerprintDiagnosticIntervalMs = 1000;
FingerprintMatch last_match;
bool has_last_match = false;
bool has_rendered = false;
Screen rendered_screen = Screen::Home;
FingerprintState rendered_fingerprint_state = FingerprintState::Initializing;
NetworkState rendered_network_state = NetworkState::Disabled;
NetworkState last_network_state = NetworkState::Disabled;
bool rendered_has_match = false;
uint16_t rendered_template_id = 0;
uint16_t rendered_confidence = 0;

const char* menu_label(uint8_t index) {
  switch (index) {
    case 0: return "Home";
    case 1: return "Hardware Test";
    case 2: return "Device Status";
    case 3: return "About";
    default: return "";
  }
}

void boot_line(const char* message, uint8_t y) {
  display.text(message, 12, y, 1, CampusIdDisplay::Muted);
  delay(120);
}

void draw_home() {
  display.clear();
  display.header("CAMPUSID", "BIOMETRIC TERMINAL");
  display.panel(10, 58, 220, 75);
  display.text(CAMPUSID_DEVICE_ID, 20, 70, 1, CampusIdDisplay::Accent);
  const FingerprintState state = fingerprint.state();
  const char* title = "TERMINAL READY";
  uint16_t color = CampusIdDisplay::Success;
  if (state == FingerprintState::Initializing) {
    title = "INITIALIZING SENSOR";
    color = CampusIdDisplay::Warning;
  } else if (state == FingerprintState::Scanning) {
    title = "READING FINGERPRINT";
    color = CampusIdDisplay::Accent;
  } else if (state == FingerprintState::Matched && has_last_match) {
    title = "FINGERPRINT MATCHED";
    color = CampusIdDisplay::Success;
  } else if (state == FingerprintState::NoMatch) {
    title = "NOT RECOGNIZED";
    color = CampusIdDisplay::Error;
  } else if (state == FingerprintState::SensorUnavailable ||
             state == FingerprintState::CommunicationError) {
    title = "SENSOR ERROR";
    color = CampusIdDisplay::Error;
  }
  display.panel(10, 148, 220, 82, color);
  display.text(title, 20, 162, 1, CampusIdDisplay::Background);
  display.text(fingerprintStateName(state), 20, 185, 1,
               CampusIdDisplay::Background);
  if (state == FingerprintState::Matched && has_last_match) {
    display.text("Template:", 20, 202, 1, CampusIdDisplay::Background);
    display.text(String(last_match.template_id).c_str(), 105, 202, 1,
                 CampusIdDisplay::Background);
    display.text("Confidence:", 20, 216, 1, CampusIdDisplay::Background);
    display.text(String(last_match.confidence).c_str(), 105, 216, 1,
                 CampusIdDisplay::Background);
  } else if (state == FingerprintState::NoMatch) {
    display.text("Try again after removal", 20, 208, 1, CampusIdDisplay::Background);
  } else if (state == FingerprintState::SensorUnavailable ||
             state == FingerprintState::CommunicationError) {
    display.text("Retrying safely", 20, 208, 1, CampusIdDisplay::Background);
  } else if (state == FingerprintState::Ready) {
    display.text("PLACE FINGER", 20, 208, 1, CampusIdDisplay::Background);
  }
  display.text("Local recognition only", 20, 250, 1, CampusIdDisplay::Muted);
  display.text("SELECT: terminal menu", 20, 270, 1, CampusIdDisplay::Muted);
  const char* network_label = "CLOUD OFFLINE";
  uint16_t network_color = CampusIdDisplay::Muted;
  if (network.state() == NetworkState::Connecting) {
    network_label = "CONNECTING";
    network_color = CampusIdDisplay::Warning;
  } else if (network.online()) {
    network_label = "ONLINE";
    network_color = CampusIdDisplay::Success;
  }
  display.text(network_label, 20, 290, 1, network_color);
}

void draw_menu() {
  display.clear();
  display.header("MENU", "SELECT AN OPERATION");
  for (uint8_t i = 0; i < 4; i++) {
    const int y = 62 + i * 38;
    if (i == menu_index) display.panel(10, y - 5, 220, 30, CampusIdDisplay::Accent);
    display.text(menu_label(i), 22, y, 2,
                 i == menu_index ? CampusIdDisplay::Background
                                 : CampusIdDisplay::Text);
  }
  display.text("UP/DOWN navigate  SELECT open", 10, 245, 1,
               CampusIdDisplay::Muted);
  display.text("BACK home", 10, 260, 1, CampusIdDisplay::Muted);
}

void draw_hardware_test() {
  const SelfTestState state = self_test.run(display, keypad);
  display.clear();
  display.header("HARDWARE TEST", "SOFTWARE CHECKS ONLY");
  display.text(state.display ? "DISPLAY API INITIALIZED" : "DISPLAY API FAILED",
               15, 62, 1, state.display ? CampusIdDisplay::Success : CampusIdDisplay::Error);
  display.text(state.keypad ? "KEYPAD        PASS" : "KEYPAD        NOT TESTED",
               15, 96, 1, state.keypad ? CampusIdDisplay::Success : CampusIdDisplay::Warning);
  display.text("LED OUTPUT     SOFTWARE CHECK", 15, 130, 1, CampusIdDisplay::Muted);
  display.text("BUZZER OUTPUT  SOFTWARE CHECK", 15, 150, 1, CampusIdDisplay::Muted);
  display.text("Press any key to verify keypad", 15, 198, 1, CampusIdDisplay::Muted);
  display.text("BACK returns to menu", 15, 220, 1, CampusIdDisplay::Muted);
}

void draw_status() {
  display.clear();
  display.header("DEVICE STATUS", "PHASE 1 TERMINAL");
  display.text("Identity", 15, 62, 1, CampusIdDisplay::Muted);
  display.text(CAMPUSID_DEVICE_ID, 15, 80, 1, CampusIdDisplay::Text);
  display.text("Firmware", 15, 116, 1, CampusIdDisplay::Muted);
  display.text(CAMPUSID_FIRMWARE_VERSION, 15, 134, 2, CampusIdDisplay::Text);
  display.text("Fingerprint", 15, 176, 1, CampusIdDisplay::Muted);
  display.text("R307S          ", 15, 198, 1,
               CampusIdDisplay::Warning);
  display.text(fingerprintStateName(fingerprint.state()), 15, 214, 1,
               CampusIdDisplay::Warning);
  display.text("Recognition only", 15, 238, 1, CampusIdDisplay::Muted);
}

void draw_about() {
  display.clear();
  display.header("ABOUT", "CAMPUSID TERMINAL");
  display.text("Firmware foundation", 15, 68, 1, CampusIdDisplay::Text);
  display.text("ESP32-WROOM-32", 15, 104, 2, CampusIdDisplay::Accent);
  display.text("Fingerprint integration is reserved", 15, 150, 1,
               CampusIdDisplay::Muted);
  display.text("for a trusted, authorized Phase 2", 15, 168, 1,
               CampusIdDisplay::Muted);
  display.text("backend workflow.", 15, 186, 1, CampusIdDisplay::Muted);
}

void render(bool force = false) {
  if (!display.available()) return;
  const FingerprintState fingerprint_state = fingerprint.state();
  const bool match_changed =
      has_last_match != rendered_has_match ||
      (has_last_match &&
       (last_match.template_id != rendered_template_id ||
        last_match.confidence != rendered_confidence));
  if (!force && has_rendered && screen == rendered_screen &&
      fingerprint_state == rendered_fingerprint_state &&
      network.state() == rendered_network_state && !match_changed) {
    return;
  }
  if (screen == Screen::Home) draw_home();
  else if (screen == Screen::Menu) draw_menu();
  else if (screen == Screen::HardwareTest) draw_hardware_test();
  else if (screen == Screen::DeviceStatus) draw_status();
  else draw_about();
  has_rendered = true;
  rendered_screen = screen;
  rendered_fingerprint_state = fingerprint_state;
  rendered_network_state = network.state();
  rendered_has_match = has_last_match;
  rendered_template_id = last_match.template_id;
  rendered_confidence = last_match.confidence;
}

void select_menu() {
  switch (menu_index) {
    case 0: screen = Screen::Home; break;
    case 1: screen = Screen::HardwareTest; break;
    case 2: screen = Screen::DeviceStatus; break;
    case 3: screen = Screen::About; break;
  }
}

void handle_key(Key key) {
  if (key == Key::None) return;
  if (screen == Screen::Home && key == Key::Select) {
    screen = Screen::Menu;
  } else if (screen == Screen::Menu) {
    if (key == Key::Up && menu_index > 0) menu_index--;
    else if (key == Key::Down && menu_index < 3) menu_index++;
    else if (key == Key::Select) select_menu();
    else if (key == Key::Back) screen = Screen::Home;
  } else if (screen == Screen::HardwareTest || screen == Screen::DeviceStatus ||
             screen == Screen::About) {
    if (key == Key::Back) screen = Screen::Menu;
  }
  render(true);
}

void setup() {
  Serial.begin(115200);
  Serial.println("\nCampusID terminal boot");
  Serial.print("Firmware: ");
  Serial.println(CAMPUSID_FIRMWARE_VERSION);
  Serial.print("R307S UART2 RX GPIO");
  Serial.print(CampusIdPins::R307Rx);
  Serial.print(" TX GPIO");
  Serial.print(CampusIdPins::R307Tx);
  Serial.println(" at 57600 baud");
  pinMode(CampusIdPins::TftDc, OUTPUT);
  digitalWrite(CampusIdPins::TftDc, LOW);
  const bool display_ready = display.begin();
  if (display_ready) {
    display.clear();
    display.header("CAMPUSID", "TERMINAL BOOT");
    boot_line("Firmware foundation", 65);
    boot_line(CAMPUSID_FIRMWARE_VERSION, 85);
    boot_line("Keypad disabled for baseline", 115);
    boot_line("Initializing indicators...", 135);
    boot_line("R307S state is on Serial", 155);
    delay(350);
  } else {
    Serial.println("TFT: unavailable; continuing without display");
  }
  fingerprint.begin();
  Serial.print("Fingerprint sensor: ");
  Serial.println(fingerprintStateName(fingerprint.state()));
#if ENABLE_KEYPAD
  keypad.begin();
#endif
  feedback.begin();
  network.begin();
  render(true);
}

void loop() {
  bool redraw = false;
  network.update(fingerprint.state() == FingerprintState::Ready);
  const uint32_t fingerprint_started = millis();
  fingerprint.update();
  const uint32_t fingerprint_duration = millis() - fingerprint_started;
  if (fingerprint_duration >= 1000) {
    Serial.print("Fingerprint update duration: ");
    Serial.print(fingerprint_duration);
    Serial.println(" ms");
  }
  if (network.state() != last_network_state) {
    last_network_state = network.state();
    redraw = true;
  }
  const FingerprintState fingerprint_state = fingerprint.state();
  if (fingerprint_state != last_fingerprint_state) {
    last_fingerprint_state = fingerprint_state;
    if (fingerprint_state == FingerprintState::NoMatch) {
      feedback.play(FeedbackKind::Rejected);
    }
    const bool diagnostic = fingerprint_state == FingerprintState::SensorUnavailable ||
                            fingerprint_state == FingerprintState::CommunicationError;
    const uint32_t now = millis();
    if (!diagnostic || !has_fingerprint_diagnostic ||
        static_cast<int32_t>(now - last_fingerprint_diagnostic) >=
            static_cast<int32_t>(FingerprintDiagnosticIntervalMs)) {
      Serial.print("Fingerprint state: ");
      Serial.println(fingerprintStateName(fingerprint_state));
      if (fingerprint_state == FingerprintState::Ready) {
        Serial.println("READY - waiting for finger");
      }
      if (diagnostic) {
        last_fingerprint_diagnostic = now;
        has_fingerprint_diagnostic = true;
      }
      redraw = fingerprint_state != FingerprintState::WaitingForRemoval;
    }
  }
  FingerprintMatch match;
  if (fingerprint.takeMatch(match)) {
    last_match = match;
    has_last_match = true;
    Serial.print("Fingerprint matched: template_id=");
    Serial.print(match.template_id);
    Serial.print(" confidence=");
    Serial.println(match.confidence);
    Serial.println("FINGERPRINT MATCHED - local recognition only.");
    feedback.play(FeedbackKind::Success);
    redraw = true;
  }
  // Consume the new match before painting so the previous template never
  // flashes on screen. Paint once per result, including the status screen.
  if (redraw && (screen == Screen::Home || screen == Screen::DeviceStatus)) {
    const uint32_t render_started = millis();
    render();
    const uint32_t render_duration = millis() - render_started;
    if (render_duration >= 1000) {
      Serial.print("TFT render duration: ");
      Serial.print(render_duration);
      Serial.println(" ms");
    }
  }
  network.update(fingerprint.state() == FingerprintState::Ready);
#if ENABLE_KEYPAD
  const Key key = keypad.poll();
  if (key != Key::None) {
    if (screen == Screen::HardwareTest && key != Key::Back) {
      feedback.play(FeedbackKind::Success);
    }
    handle_key(key);
  }
#endif
  feedback.update();
}
