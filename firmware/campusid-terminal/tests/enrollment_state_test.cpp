#include "../fingerprint_service.h"

#include <cassert>

static void tick(FingerprintService& service, uint32_t elapsed = 250) {
  test_millis += elapsed;
  service.update();
}

static void start(FingerprintService& service, uint16_t reserved_slot = 2) {
  sensor_fixture = SensorFixture{};
  sensor_fixture.occupied[0] = 2;  // Existing template #1 remains untouched.
  sensor_fixture.images = {FINGERPRINT_OK, FINGERPRINT_NOFINGER, FINGERPRINT_OK};
  test_millis = 0;
  service.begin();
  assert(service.state() == FingerprintState::Ready);
  assert(service.capacity() == 64);
  assert(service.enrollmentState() == EnrollmentState::Idle);
  assert(service.beginEnrollment("Test student", reserved_slot));
}

static void prepare(FingerprintService& service) {
  tick(service);
  assert(service.enrollmentState() == EnrollmentState::CaptureFirst);
}

static void captureToStore(FingerprintService& service) {
  prepare(service);
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
  assert(service.enrollmentState() == EnrollmentState::StoringModel);
}

int main() {
  bool success;
  uint16_t slot;
  String error;
  {
    FingerprintService service;
    sensor_fixture = SensorFixture{};
    sensor_fixture.capacity = 72;
    sensor_fixture.occupied[0] = 2;
    service.begin();
    assert(service.capacity() == 72 && service.templateCount() == 1);
    assert(sensor_fixture.empty_calls == 0);  // Normal boot never wipes data.
    assert(service.resetFingerprintDatabase());
    assert(sensor_fixture.empty_calls == 1);
    assert(service.templateCount() == 0);
  }
  {
    FingerprintService service;
    sensor_fixture = SensorFixture{};
    sensor_fixture.capacity = 0;
    service.begin();
    assert(service.state() == FingerprintState::SensorUnavailable);
  }
  {
    FingerprintService service;
    start(service);
    captureToStore(service);
    tick(service);
    assert(service.enrollmentState() == EnrollmentState::AwaitingAck);
    assert(service.takeEnrollmentResult(success, slot, error) && success && slot == 2);
    for (unsigned i = 0; i < 20; ++i) tick(service, 1000);
    assert(sensor_fixture.stores == 1);  // ACK retries cannot store twice.
    assert(!service.takeEnrollmentResult(success, slot, error));
    tick(service, 11000);
    assert(service.enrollmentState() == EnrollmentState::Failed);
    tick(service, 4000);
    tick(service);
    service.enrollmentAcknowledged(true);
    assert(service.enrollmentState() == EnrollmentState::Success);
    assert(service.enrollmentTemplateId() == 2 && sensor_fixture.stores == 1);
  }
  {
    FingerprintService service;
    start(service);
    prepare(service);
    tick(service, 60000);
    assert(service.takeEnrollmentResult(success, slot, error) && !success);
    assert(sensor_fixture.stores == 0);
  }
  {
    FingerprintService service;
    start(service);
    sensor_fixture.search = FINGERPRINT_OK;
    prepare(service);
    tick(service);
    tick(service);
    tick(service);
    assert(service.takeEnrollmentResult(success, slot, error) && !success);
    assert(sensor_fixture.stores == 0);
  }
  {
    FingerprintService service;
    start(service);
    captureToStore(service);
    sensor_fixture.store = FINGERPRINT_FLASHERR;
    tick(service);
    assert(service.takeEnrollmentResult(success, slot, error) && !success);
    assert(sensor_fixture.stores == 1);
    assert(sensor_fixture.occupied[0] == 2);  // No new stored template.
  }
  {
    FingerprintService service;
    start(service);
    sensor_fixture.create = FINGERPRINT_ENROLLMISMATCH;
    prepare(service);
    tick(service);
    tick(service);
    tick(service);
    tick(service);
    tick(service);
    tick(service);
    tick(service);
    assert(service.takeEnrollmentResult(success, slot, error) && !success);
    assert(sensor_fixture.stores == 0);
  }
  {
    FingerprintService service;
    sensor_fixture = SensorFixture{};
    test_millis = 0;
    service.begin();
    assert(!service.beginEnrollment("Test student", 65));
    assert(service.enrollmentState() == EnrollmentState::AwaitingAck);
    assert(service.takeEnrollmentResult(success, slot, error) && !success);
    assert(sensor_fixture.stores == 0);
  }
}
