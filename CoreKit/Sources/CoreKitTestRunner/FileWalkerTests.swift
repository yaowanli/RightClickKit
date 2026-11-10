import Foundation
import CoreKit

func runFileWalkerTests() {
    test("FileWalker:遍历嵌套文件") {
        let (root, _) = try makeTree()
        var visited = Set<String>()
        FileWalker.walk(root) { visited.insert($0.lastPathComponent).inserted }
        expectEqual(visited, Set(["root", "a.txt", "sub", "b.txt"]))
    }
    test("FileWalker:总大小只统计文件字节(不含目录元数据)") {
        let (root, _) = try makeTree()
        expectEqual(FileWalker.totalSize(of: [root]), Int64(9)) // a.txt 5B + b.txt 4B
    }
}

/// root/  a.txt(5B)  sub/b.txt(4B)
private func makeTree() throws -> (URL, [URL]) {
    let parent = FileManager.default.temporaryDirectory
        .appendingPathComponent("walk-\(UUID().uuidString)")
    let root = parent.appendingPathComponent("root")
    let sub = root.appendingPathComponent("sub")
    try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
    let a = root.appendingPathComponent("a.txt")
    let b = sub.appendingPathComponent("b.txt")
    try Data("hello".utf8).write(to: a)
    try Data("abcd".utf8).write(to: b)
    return (root, [a, b])
}
