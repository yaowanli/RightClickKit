import Foundation

public enum RenameRule {
    case prefix(String)                                  // 加在主名前
    case suffix(String)                                  // 加在扩展名前
    case sequence(base: String, start: Int, width: Int)  // base+序号,丢弃原名
    case replace(find: String, replacement: String)      // 全名查找替换
}

public enum RenamePlanner {
    public static func plan(names: [String], rule: RenameRule) -> [(old: String, new: String)] {
        names.enumerated().map { i, name in
            let ext = (name as NSString).pathExtension
            let stem = ext.isEmpty ? name : String(name.dropLast(ext.count + 1))
            let new: String
            switch rule {
            case .prefix(let p): new = p + stem + (ext.isEmpty ? "" : "." + ext)
            case .suffix(let s): new = stem + s + (ext.isEmpty ? "" : "." + ext)
            case .sequence(let base, let start, let width):
                let num = String(start + i, radix: 10)
                let padded = String(repeating: "0", count: max(0, width - num.count)) + num
                new = base + padded + (ext.isEmpty ? "" : "." + ext)
            case .replace(let find, let rep): new = name.replacingOccurrences(of: find, with: rep)
            }
            return (name, new)
        }
    }

    /// 返回批次内出现 ≥2 次的新名字
    public static func collisions(in pairs: [(old: String, new: String)]) -> [String] {
        var counts: [String: Int] = [:]
        for p in pairs { counts[p.new, default: 0] += 1 }
        return counts.filter { $0.value > 1 }.map { $0.key }.sorted()
    }
}
