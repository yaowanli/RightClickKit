import Foundation

public enum PathUtils {
    /// 在 directory 下返回不冲突的名字:base 或 "base N"+"ext"
    public static func uniqueName(in directory: URL, base: String, ext: String) -> String {
        func candidate(_ i: Int) -> String {
            let stem = i == 1 ? base : "\(base) \(i)"
            return ext.isEmpty ? stem : "\(stem).\(ext)"
        }
        var i = 1
        while i < 10_000,
              FileManager.default.fileExists(atPath: directory.appendingPathComponent(candidate(i)).path) {
            i += 1
        }
        return candidate(i)
    }
}
