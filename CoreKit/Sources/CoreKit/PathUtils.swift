import Foundation

public enum PathUtils {
    /// 在 directory 下返回不冲突的名字:base 或 "base N"+"ext"
    public static func uniqueName(in directory: URL, base: String, ext: String) -> String {
        func candidate(_ i: Int) -> String {
            let stem = i == 1 ? base : "\(base) \(i)"
            return ext.isEmpty ? stem : "\(stem).\(ext)"
        }
        var i = 1
        // 不跟随符号链接(lstat 语义):同名悬空链接也算已存在,
        // 否则 copyItem/createFile 会撞掉链接,把内容写到链接目标路径
        while i < 10_000,
              (try? FileManager.default.attributesOfItem(
                  atPath: directory.appendingPathComponent(candidate(i)).path)) != nil {
            i += 1
        }
        return candidate(i)
    }
}
