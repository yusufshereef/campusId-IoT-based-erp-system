#include "../fingerprint_service.h"
#include <cassert>

static void tick(FingerprintService& service, uint32_t elapsed = 250) {
  test_millis += elapsed;
  service.update();
}

static void start(FingerprintService& service, const uint8_t reserved[128]) {
  sensor_fixture = SensorFixture{};
  sensor_fixture.occupied[0] = 2;  // Preserve orphan slot 1.
  sensor_fixture.images = {FINGERPRINT_OK, FINGERPRINT_NOFINGER, FINGERPRINT_OK};
  test_millis = 0;
  service.begin();
  service.beginEnrollment("Test student", reserved, true);
}

static void capture(FingerprintService& service) {
  tick(service);
  assert(service.enrollmentState() == EnrollmentState::ConvertFirstCapture);
  tick(service);
  assert(service.enrollmentState() == EnrollmentState::CheckExistingTemplate);
  tick(service);
  assert(service.enrollmentState() == EnrollmentState::WaitingForRemoval);
  tick(service);
  assert(service.enrollmentState() == EnrollmentState::CaptureSecond);
  tick(service);
  assert(service.enrollmentState() == EnrollmentState::ConvertSecondCapture);
  tick(service);
  assert(service.enrollmentState() == EnrollmentState::CreatingModel);
  tick(service);
  assert(service.enrollmentState() == EnrollmentState::CheckingStorage);
  tick(service);
  assert(service.enrollmentState() == EnrollmentState::ReadingStorageIndex);
  tick(service);
  assert(service.enrollmentState() == EnrollmentState::StoringModel);
  tick(service);
  assert(service.enrollmentState() == EnrollmentState::AwaitingAck);
}

int main() {
  uint8_t reserved[128] = {};
  bool success;
  uint16_t slot;
  String error;
  {
    FingerprintService service;
    start(service, reserved);
    capture(service);
    assert(service.takeEnrollmentResult(success, slot, error) && success && slot == 2);
    // Repeated unsuccessful ACK attempts never re-enter capture/store.
    for (unsigned i = 0; i < 20; ++i) tick(service, 1000);
    assert(sensor_fixture.stores == 1);
    assert(!service.takeEnrollmentResult(success, slot, error));
    tick(service, 11000);
    assert(service.enrollmentState() == EnrollmentState::Failed);
    tick(service, 4000);
    tick(service);
    assert(service.state() == FingerprintState::Ready);
    service.enrollmentAcknowledged(true); // Same stored result confirmed late.
    assert(service.enrollmentState() == EnrollmentState::Success);
    assert(service.enrollmentTemplateId() == 2 && sensor_fixture.stores == 1);
  }
  {
    FingerprintService service;
    start(service, reserved);
    sensor_fixture.images.clear();
    tick(service, 60000);
    assert(service.takeEnrollmentResult(success, slot, error) && !success);
    assert(sensor_fixture.stores == 0);
    service.enrollmentAcknowledged(true);
    assert(service.enrollmentState() == EnrollmentState::Failed);
  }
  {
    FingerprintService service;
    start(service, reserved);
    sensor_fixture.search = FINGERPRINT_OK; // Already stored, including orphan #2.
    tick(service);
    tick(service);
    tick(service);
    assert(service.takeEnrollmentResult(success, slot, error) && !success);
    assert(sensor_fixture.stores == 0);
  }
  for (bool bad_checksum : {false, true}) {
    FingerprintService service;
    start(service, reserved);
    sensor_fixture.index_available = true;
    sensor_fixture.corrupt_checksum = bad_checksum;
    for (unsigned i = 0; i < 10; ++i) tick(service);
    if (bad_checksum) {
      assert(service.takeEnrollmentResult(success, slot, error) && !success);
      assert(sensor_fixture.stores == 0);
    } else {
      assert(service.takeEnrollmentResult(success, slot, error) && success && slot == 2);
      assert(sensor_fixture.stores == 1);
    }
  }
  {
    FingerprintService service;
    reserved[0] = 4; // Missing physical slot 2 remains reserved by backend.
    start(service, reserved);
    capture(service);
    assert(service.takeEnrollmentResult(success, slot, error) && success && slot == 3);
    assert(sensor_fixture.stores == 1);
  }
}
