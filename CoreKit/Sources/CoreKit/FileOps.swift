import Foundation

public enum FileOps {
    /// 移动;目标已存在时自动命名 "x 2.ext"、"x 3.ext"…
    @discardableResult
    public static func moveWithoutClobber(from: URL, to: URL) throws -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: to.path) else {
            try fm.moveItem(at: from, to: to)
            return to
        }
        let dir = to.deletingLastPathComponent()
        let ext = to.pathExtension
        let base = ext.isEmpty ? to.lastPathComponent : String(to.lastPathComponent.dropLast(ext.count + 1))
        var i = 2
        var candidate = to
        while fm.fileExists(atPath: candidate.path) {
            let stem = i == 1 ? base : "\(base) \(i)"
            candidate = dir.appendingPathComponent(ext.isEmpty ? stem : "\(stem).\(ext)")
            i += 1
        }
        try fm.moveItem(at: from, to: candidate)
        return candidate
    }

    /// 解除锁定(UF_IMMUTABLE)并给属主加写权限(递归)
    public static func makeWritable(_ url: URL) {
        let fm = FileManager.default
        FileWalker.walk(url) { f in
            try? fm.setAttributes([.immutable: false], ofItemAtPath: f.path)
            if let mode = ((try? fm.attributesOfItem(atPath: f.path))?[.posixPermissions] as? NSNumber)?.int16Value {
                try? fm.setAttributes([.posixPermissions: NSNumber(value: mode | 0o200)], ofItemAtPath: f.path)
            }
            return true
        }
    }
}
