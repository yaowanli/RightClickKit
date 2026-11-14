import Foundation
import CoreKit

func runFileOpsTests() {
    test("FileOps:移动冲突时自动改名为 x 2.ext") {
        let dir = try makeTempDir()
        // 源与目标必须是不同路径(同路径会变成"移到自己"的退化场景)
        let srcDir = try makeTempDir()
        let a = srcDir.appendingPathComponent("x.txt")
        try Data("1".utf8).write(to: a)
        let dst = dir.appendingPathComponent("x.txt")
        try Data("2".utf8).write(to: dst)
        let final = try FileOps.moveWithoutClobber(from: a, to: dst)
        expectEqual(final.lastPathComponent, "x 2.txt")
        expectEqual(try String(contentsOf: final, encoding: .utf8), "1")
        expectEqual(try String(contentsOf: dst, encoding: .utf8), "2")
    }
    test("FileOps:无冲突直接移动") {
        let dir = try makeTempDir()
        let a = dir.appendingPathComponent("a.txt")
        try Data("1".utf8).write(to: a)
        let dst = dir.appendingPathComponent("x.txt")
        let final = try FileOps.moveWithoutClobber(from: a, to: dst)
        expectEqual(final, dst)
        expectEqual(try String(contentsOf: dst, encoding: .utf8), "1")
        expectEqual(FileManager.default.fileExists(atPath: a.path), false)
    }
    test("FileOps:冲突且无扩展名时移为 x 2") {
        let dir = try makeTempDir()
        let srcDir = try makeTempDir()
        let a = srcDir.appendingPathComponent("x")
        try Data("1".utf8).write(to: a)
        let dst = dir.appendingPathComponent("x")
        try Data("2".utf8).write(to: dst)
        let final = try FileOps.moveWithoutClobber(from: a, to: dst)
        expectEqual(final.lastPathComponent, "x 2")
        expectEqual(try String(contentsOf: final, encoding: .utf8), "1")
        expectEqual(try String(contentsOf: dst, encoding: .utf8), "2")
    }
    test("FileOps:目标为悬空符号链接时避让且链接保留") {
        let dir = try makeTempDir()
        let link = dir.appendingPathComponent("x.txt")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "/nonexistent-rck-target")
        let srcDir = try makeTempDir()
        let a = srcDir.appendingPathComponent("a.txt")
        try Data("1".utf8).write(to: a)
        let final = try FileOps.moveWithoutClobber(from: a, to: link)
        expectEqual(final.lastPathComponent, "x 2.txt")
        // 链接原样保留(lstat 不跟随链接,确认类型与指向均未变)
        let attrs = try FileManager.default.attributesOfItem(atPath: link.path)
        expectEqual(attrs[.type] as? FileAttributeType, .typeSymbolicLink)
        expectEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), "/nonexistent-rck-target")
    }
    test("FileOps:授权限解除锁定并加 u+w") {
        let dir = try makeTempDir()
        let f = dir.appendingPathComponent("y.txt")
        try Data("y".utf8).write(to: f)
        let fm = FileManager.default
        try fm.setAttributes([.posixPermissions: 0o444, .immutable: true], ofItemAtPath: f.path)
        FileOps.makeWritable(f)
        let attrs = try fm.attributesOfItem(atPath: f.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.int16Value ?? 0
        expectEqual(perms & 0o200, Int16(0o200))
        expectEqual(attrs[.immutable] as? Bool, false)
    }
    test("FileOps:removeAll 全部成功") {
        let dir = try makeTempDir()
        var files: [URL] = []
        for name in ["a.txt", "b.txt", "c.txt"] {
            let f = dir.appendingPathComponent(name)
            try Data("1".utf8).write(to: f)
            files.append(f)
        }
        let r = FileOps.removeAll(files)
        expectEqual(r.deleted, 3)
        expectEqual(r.firstError, nil)
        expectTrue(files.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) }, "三项都应已不存在")
    }
    test("FileOps:removeAll 部分失败不中断") {
        let dir = try makeTempDir()
        let a = dir.appendingPathComponent("a.txt")
        let b = dir.appendingPathComponent("b.txt")
        try Data("1".utf8).write(to: a)
        try Data("2".utf8).write(to: b)
        let ghost = dir.appendingPathComponent("not-existed.txt")
        // 不存在的路径夹在中间:验证单项失败后继续删后续项
        let r = FileOps.removeAll([a, ghost, b])
        expectEqual(r.deleted, 2)
        expectTrue(r.firstError != nil, "首个错误不应为 nil")
        expectTrue(!FileManager.default.fileExists(atPath: a.path)
            && !FileManager.default.fileExists(atPath: b.path), "失败后仍应删完剩余项")
    }
}
