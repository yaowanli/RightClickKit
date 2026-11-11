import Foundation
import CoreKit

/// unzip -Z1 列出 zip 条目名(仅名字,一行一个)。仅适合 ASCII 名:
/// ditto 不设 zip UTF-8 标志,unzip 按CP437 显示中文名会乱码(Mac 解压不受影响)
private func zipEntries(_ url: URL) throws -> [String] {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
    p.arguments = ["-Z1", url.path]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    try p.run()
    p.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    expectEqual(p.terminationStatus, Int32(0))
    return String(decoding: data, as: UTF8.self)
        .split(separator: "\n").map(String.init)
        .filter { !$0.isEmpty && !$0.hasPrefix("__MACOSX") && !$0.hasPrefix("._") }
}

/// ditto -x 解压回读:验证中文文件名在 Mac 端无损往返
private func unzipWithDitto(_ zip: URL, to dir: URL) throws -> [String] {
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    p.arguments = ["-x", "-k", zip.path, dir.path]
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    try p.run()
    p.waitUntilExit()
    expectEqual(p.terminationStatus, Int32(0))
    return try FileManager.default.contentsOfDirectory(atPath: dir.path)
}

func runZipperTests() {
    test("Zipper:单文件压缩后直接位于 zip 根") {
        let dir = try makeTempDir()
        let a = dir.appendingPathComponent("报告.txt")
        try Data("hello".utf8).write(to: a)
        let result = Zipper.zip(items: [a])
        guard case .success(let out) = result else {
            expectTrue(false, "压缩失败:\(result)"); return
        }
        expectEqual(out.lastPathComponent, "报告.zip")
        // 中文文件名经 ditto 解压应无损还原
        let extracted = try unzipWithDitto(out, to: dir.appendingPathComponent("x1"))
        expectEqual(extracted, ["报告.txt"])
        expectEqual(try String(contentsOf: dir.appendingPathComponent("x1/报告.txt"), encoding: .utf8), "hello")
        // 暂存/临时产物不留残留
        let remain = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        expectTrue(remain.allSatisfy { $0 == "报告.txt" || $0 == "报告.zip" || $0 == "x1" }, "目录有残留:\(remain)")
    }
    test("Zipper:单文件夹压缩保留一层目录名") {
        let dir = try makeTempDir()
        let sub = dir.appendingPathComponent("工程")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: false)
        try Data("x".utf8).write(to: sub.appendingPathComponent("a.txt"))
        let result = Zipper.zip(items: [sub])
        guard case .success(let out) = result else {
            expectTrue(false, "压缩失败:\(result)"); return
        }
        let extracted = try unzipWithDitto(out, to: dir.appendingPathComponent("x2"))
        expectEqual(try zipEntries(out).count, 2)
        expectTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("x2/工程/a.txt").path),
                   "解压后缺 工程/a.txt")
        expectEqual(extracted, ["工程"])
    }
    test("Zipper:多选压缩各项平铺在根") {
        let dir = try makeTempDir()
        var files: [URL] = []
        for name in ["a.txt", "b.txt", "c.md"] {
            let f = dir.appendingPathComponent(name)
            try Data("v".utf8).write(to: f)
            files.append(f)
        }
        let result = Zipper.zip(items: files)
        guard case .success(let out) = result else {
            expectTrue(false, "压缩失败:\(result)"); return
        }
        expectEqual(out.lastPathComponent, "a.zip")
        expectEqual(Set(try zipEntries(out)), Set(["a.txt", "b.txt", "c.md"]))
    }
    test("Zipper:多选重名直接报错不产出") {
        let dir = try makeTempDir()
        let d1 = dir.appendingPathComponent("d1"), d2 = dir.appendingPathComponent("d2")
        try FileManager.default.createDirectory(at: d1, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: d2, withIntermediateDirectories: false)
        try Data("1".utf8).write(to: d1.appendingPathComponent("same.txt"))
        try Data("2".utf8).write(to: d2.appendingPathComponent("same.txt"))
        let result = Zipper.zip(items: [d1.appendingPathComponent("same.txt"), d2.appendingPathComponent("same.txt")])
        guard case .failure(let msg) = result else {
            expectTrue(false, "重名应失败,实际:\(result)"); return
        }
        expectTrue(msg.message.contains("重名"), "错误信息应含重名:\(msg.message)")
    }
    test("Zipper:locate7z 返回值与环境一致") {
        // 不强求机器装了 7zz:无论装没装,断言返回值与 isExecutableFile 一致
        let found = Zipper.locate7z()
        let paths = ["/opt/homebrew/bin/7zz", "/opt/homebrew/bin/7z", "/opt/homebrew/bin/7za",
                     "/usr/local/bin/7zz", "/usr/local/bin/7z", "/usr/local/bin/7za"]
        expectEqual(found, paths.first { FileManager.default.isExecutableFile(atPath: $0) })
    }
}
