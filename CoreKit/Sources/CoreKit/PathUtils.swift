import Foundation

public enum PathUtils {
    /// 在 directory 下返回不冲突的名字:base 或 "base N"+"ext"
    public static func uniqueName(in directory: URL, base: String, ext: String) -> String {
        func candidate(_ i: Int) -> String {
            let stem = i == 1 ? base : "\(base) \(i)"
            return ext.isEmpty ? stem : "\(stem).\(ext)"
        }
        var i = 1
        while i < 10_000, pathOccupied(directory.appendingPathComponent(candidate(i)).path) { i += 1 }
        return candidate(i)
    }

    /// 路径是否已占用:lstat 语义(attributesOfItem 不跟随符号链接),
    /// 同名悬空链接也算占用,避免被 createFile/moveItem 顶掉;
    /// 仅「无此文件」(NSFileReadNoSuchFileError=260 / NSFileNoSuchFileError=4)视为空闲,
    /// 其余错误(如父目录无权限 257)按占用避让——误判占用只跳号,误判空闲会覆盖。
    static func pathOccupied(_ path: String) -> Bool {
        do {
            _ = try FileManager.default.attributesOfItem(atPath: path)
            return true
        } catch let e as NSError {
            let isNoSuchFile = e.domain == NSCocoaErrorDomain
                && (e.code == NSFileReadNoSuchFileError || e.code == NSFileNoSuchFileError)
            return !isNoSuchFile
        }
    }
}
