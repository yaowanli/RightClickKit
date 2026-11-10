import Foundation

public enum RenameRule {
    case prefix(String)                                  // 加在主名前
    case suffix(String)                                  // 加在扩展名前
    case sequence(base: String, start: Int, width: Int)  // base+序号,丢弃原名
    case replace(find: String, replacement: String)      // 全名查找替换
}

public enum RenamePlanner {
    /// 纯名字级规划:返回与输入等长且同序的 (old, new) 列表,identity 对(old==new)包含在内,
    /// 由调用方过滤。只负责名字变换;批内重复与链式冲突用 collisions(in:) 检测,
    /// 批外磁盘同名冲突由调用方在预览层检查(需要文件系统,这里保持纯函数)。
    /// 已知限制:replace 为字面匹配,不处理 Unicode NFC/NFD 等价。
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

    /// 返回批次内不允许直接执行的新名:出现 ≥2 次的新名,以及链式冲突
    /// (某项的 new 等于另一非自身项的 old,如 1.txt→002.txt 而 002.txt 也在批次内)。
    /// identity 对(old==new)不参与链式判定。排序返回,输出确定。
    public static func collisions(in pairs: [(old: String, new: String)]) -> [String] {
        var dupNew: [String: Int] = [:]
        for p in pairs { dupNew[p.new, default: 0] += 1 }
        var out = Set(dupNew.filter { $0.value > 1 }.map { $0.key })
        let olds = Set(pairs.map { $0.old })
        for p in pairs where p.new != p.old && olds.contains(p.new) {
            out.insert(p.new)
        }
        return out.sorted()
    }
}
