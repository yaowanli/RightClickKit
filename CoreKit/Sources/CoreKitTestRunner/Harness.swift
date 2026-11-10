import Foundation

var _failures = 0
var _assertions = 0
var _testsRun = 0
var _currentTest = ""
var _currentTestFailed = false
var _tempDirs: [URL] = []

func test(_ name: String, _ body: () throws -> Void) {
    _testsRun += 1
    _currentTest = name
    _currentTestFailed = false
    do {
        try body()
    } catch {
        print("  ❌ (\(name)) 抛错:\(error)")
        _failures += 1
        _currentTestFailed = true
    }
    print(_currentTestFailed ? "❌ \(name)" : "✅ \(name)")
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T,
                               file: StaticString = #file, line: UInt = #line) {
    _assertions += 1
    if actual != expected {
        print("  ❌ (\(file):\(line)): 期望 \(expected),实际 \(actual)")
        _failures += 1
        _currentTestFailed = true
    }
}

func expectTrue(_ cond: Bool, _ label: String,
                file: StaticString = #file, line: UInt = #line) {
    _assertions += 1
    if !cond {
        print("  ❌ (\(file):\(line)): \(label)")
        _failures += 1
        _currentTestFailed = true
    }
}

func makeTempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("ck-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    _tempDirs.append(dir)
    return dir
}

/// 退出前统一清理测试临时目录
func cleanupTempDirs() {
    for dir in _tempDirs {
        try? FileManager.default.removeItem(at: dir)
    }
}
