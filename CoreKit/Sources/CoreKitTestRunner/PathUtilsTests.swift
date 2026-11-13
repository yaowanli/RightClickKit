import Foundation
import CoreKit

func runPathUtilsTests() {
    test("PathUtils:空闲时返回 base") {
        let dir = try makeTempDir()
        expectEqual(PathUtils.uniqueName(in: dir, base: "未命名文件夹", ext: ""), "未命名文件夹")
        expectEqual(PathUtils.uniqueName(in: dir, base: "未命名文件", ext: "txt"), "未命名文件.txt")
    }
    test("PathUtils:已存在则加空格编号") {
        let dir = try makeTempDir()
        FileManager.default.createFile(atPath: dir.appendingPathComponent("新建文本文档.txt").path, contents: Data())
        expectEqual(PathUtils.uniqueName(in: dir, base: "新建文本文档", ext: "txt"), "新建文本文档 2.txt")
    }
    test("PathUtils:连续已存在时继续递增") {
        let dir = try makeTempDir()
        for i in [1, 2] {
            let name = i == 1 ? "草稿" : "草稿 2"
            FileManager.default.createFile(atPath: dir.appendingPathComponent(name).path, contents: Data())
        }
        expectEqual(PathUtils.uniqueName(in: dir, base: "草稿", ext: ""), "草稿 3")
    }
    test("PathUtils:同名悬空符号链接也算冲突") {
        let dir = try makeTempDir()
        let link = dir.appendingPathComponent("a.txt")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "/nonexistent-rck-target")
        let name = PathUtils.uniqueName(in: dir, base: "a", ext: "txt")
        expectEqual(name, "a 2.txt")
    }
    test("PathUtils:目录存在也算冲突(回归)") {
        let dir = try makeTempDir()
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("未命名文件夹"), withIntermediateDirectories: false)
        expectEqual(PathUtils.uniqueName(in: dir, base: "未命名文件夹", ext: ""), "未命名文件夹 2")
    }
}
