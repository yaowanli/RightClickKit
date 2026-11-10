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
}
