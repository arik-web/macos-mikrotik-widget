import Foundation

// A ~100 line test harness standing in for XCTest.
//
// XCTest and swift-testing both ship inside Xcode.app, so neither is available
// to a Command Line Tools toolchain. This keeps the suite runnable with
// `swift run MikroTikKitTests` on a machine that has no Xcode installed.

struct TestFailure: Error {
    let message: String
}

enum Report {
    static var suiteName = ""
    static var testName = ""
    static var assertions = 0
    static var failures: [String] = []
    static var testsRun = 0
    static var testsFailed = 0
}

func suite(_ name: String, _ body: () -> Void) {
    Report.suiteName = name
    print("\n\u{001B}[1m\(name)\u{001B}[0m")
    body()
}

func test(_ name: String, _ body: () throws -> Void) {
    Report.testName = name
    Report.testsRun += 1
    let failuresBefore = Report.failures.count

    do {
        try body()
    } catch let failure as TestFailure {
        recordFailure(failure.message)
    } catch {
        recordFailure("threw unexpected error: \(error)")
    }

    if Report.failures.count == failuresBefore {
        print("  \u{001B}[32m✓\u{001B}[0m \(name)")
    } else {
        Report.testsFailed += 1
        print("  \u{001B}[31m✗\u{001B}[0m \(name)")
        for failure in Report.failures[failuresBefore...] {
            print("      \(failure)")
        }
    }
}

private func recordFailure(_ message: String, file: StaticString = #file, line: UInt = #line) {
    let fileName = URL(fileURLWithPath: String(describing: file)).lastPathComponent
    Report.failures.append("\(message)  (\(fileName):\(line))")
}

// MARK: - Assertions

func assertTrue(
    _ condition: Bool,
    _ label: String = "",
    file: StaticString = #file,
    line: UInt = #line
) {
    Report.assertions += 1
    guard !condition else { return }
    recordFailure("expected true\(label.isEmpty ? "" : " — \(label)")", file: file, line: line)
}

func assertFalse(
    _ condition: Bool,
    _ label: String = "",
    file: StaticString = #file,
    line: UInt = #line
) {
    assertTrue(!condition, label, file: file, line: line)
}

func assertEqual<T: Equatable>(
    _ actual: T,
    _ expected: T,
    _ label: String = "",
    file: StaticString = #file,
    line: UInt = #line
) {
    Report.assertions += 1
    guard actual != expected else { return }
    recordFailure(
        "expected \(expected) but got \(actual)\(label.isEmpty ? "" : " — \(label)")",
        file: file,
        line: line
    )
}

func assertEqual(
    _ actual: Double,
    _ expected: Double,
    accuracy: Double,
    _ label: String = "",
    file: StaticString = #file,
    line: UInt = #line
) {
    Report.assertions += 1
    guard abs(actual - expected) > accuracy else { return }
    recordFailure(
        "expected \(expected) ±\(accuracy) but got \(actual)\(label.isEmpty ? "" : " — \(label)")",
        file: file,
        line: line
    )
}

func assertNil<T>(
    _ value: T?,
    _ label: String = "",
    file: StaticString = #file,
    line: UInt = #line
) {
    Report.assertions += 1
    guard let value else { return }
    recordFailure("expected nil but got \(value)\(label.isEmpty ? "" : " — \(label)")", file: file, line: line)
}

func assertLessThan<T: Comparable>(
    _ lhs: T,
    _ rhs: T,
    _ label: String = "",
    file: StaticString = #file,
    line: UInt = #line
) {
    Report.assertions += 1
    guard !(lhs < rhs) else { return }
    recordFailure("expected \(lhs) < \(rhs)\(label.isEmpty ? "" : " — \(label)")", file: file, line: line)
}

/// Fails the current test and stops it, mirroring `XCTUnwrap`.
func unwrap<T>(
    _ value: T?,
    _ label: String = "value",
    file: StaticString = #file,
    line: UInt = #line
) throws -> T {
    Report.assertions += 1
    guard let value else {
        let fileName = URL(fileURLWithPath: String(describing: file)).lastPathComponent
        throw TestFailure(message: "expected non-nil \(label)  (\(fileName):\(line))")
    }
    return value
}

func finish() -> Never {
    print("\n" + String(repeating: "─", count: 52))
    if Report.failures.isEmpty {
        print(
            "\u{001B}[32mPASS\u{001B}[0m  \(Report.testsRun) tests, "
            + "\(Report.assertions) assertions, 0 failures"
        )
        exit(0)
    }
    print(
        "\u{001B}[31mFAIL\u{001B}[0m  \(Report.testsFailed)/\(Report.testsRun) tests failed, "
        + "\(Report.failures.count) failed assertions"
    )
    exit(1)
}
