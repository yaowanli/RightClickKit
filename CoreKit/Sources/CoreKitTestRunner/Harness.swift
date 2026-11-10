import Foundation

var _failures = 0
var _currentTest = ""

func test(_ name: String, _ body: () throws -> Void) {
    _currentTest = name
    do {
        try body()
        print("✅ \(name)")
    } catch {
        print("❌ \(name): 抛错 \(error)")
        _failures += 1
    }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T,
                               file: StaticString = #file, line: UInt = #line) {
    if actual != expected {
        print("❌ \(_currentTest)(\(file):\(line)): 期望 \(expected),实际 \(actual)")
        _failures += 1
    }
}

func expectTrue(_ cond: Bool, _ label: String,
                file: StaticString = #file, line: UInt = #line) {
    if !cond {
        print("❌ \(_currentTest)(\(file):\(line)): \(label)")
        _failures += 1
    }
}

func makeTempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("ck-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}
