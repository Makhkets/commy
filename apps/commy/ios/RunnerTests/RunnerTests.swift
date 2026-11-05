import Libbox
import XCTest

@testable import Runner

final class RunnerTests: XCTestCase {
  func testCoreLogLevelsPreserveErrorSeverity() {
    let events = CoreEvents()
    var received: [[String: Any]] = []
    events.emit = { name, value in
      XCTAssertEqual(name, "logs")
      received = value as! [[String: Any]]
    }
    let iterator = TestLogIterator()
    events.writeLogs(iterator)
    XCTAssertEqual(
      received.compactMap { $0["level"] as? String },
      ["fatal", "fatal", "error", "warn", "info", "debug", "trace"])
  }

  func testUnavailableTrafficDoesNotLookLikeZeroTraffic() {
    let events = CoreEvents()
    var count = 0
    events.emit = { _, _ in count += 1 }
    let status = LibboxStatusMessage()
    status.trafficAvailable = false
    events.writeStatus(status)
    XCTAssertEqual(count, 0)
    status.trafficAvailable = true
    events.writeStatus(status)
    XCTAssertEqual(count, 1)
  }
}

private final class TestLogIterator: NSObject, LibboxLogIteratorProtocol {
  private var index: Int32 = 0
  func hasNext() -> Bool { index <= 6 }
  func len() -> Int32 { 7 - index }
  func next() -> LibboxLogEntry? {
    guard hasNext() else { return nil }
    let entry = LibboxLogEntry()
    entry.level = index
    entry.message = "test"
    index += 1
    return entry
  }
}
