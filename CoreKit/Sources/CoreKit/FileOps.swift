import Foundation

public enum FileOps {
    /// 移动;目标已存在时自动命名 "x 2.ext"、"x 3.ext"…
    @discardableResult
    public static func moveWithoutClobber(from: URL, to: URL) throws -> URL {
        let fm = FileManager.default
        guard PathUtils.pathOccupied(to.path) else {
            try fm.moveItem(at: from, to: to)
            return to
        }
        let dir = to.deletingLastPathComponent()
        let ext = to.pathExtension
        let base = ext.isEmpty ? to.lastPathComponent : String(to.lastPathComponent.dropLast(ext.count + 1))
        var i = 2
        var candidate = to
        while PathUtils.pathOccupied(candidate.path) {
            let stem = "\(base) \(i)"
            candidate = dir.appendingPathComponent(ext.isEmpty ? stem : "\(stem).\(ext)")
            i += 1
        }
        try fm.moveItem(at: from, to: candidate)
        return candidate
    }

    /// 解除锁定(UF_IMMUTABLE)并给属主加写权限(递归)。
    /// 返回成功处理的节点数(目录与文件同口径:两步 setAttributes 都成功才计 1);
    /// 失败常见于属主不是当前用户,调用方按成功/失败分口径提示。
    @discardableResult
    public static func makeWritable(_ url: URL) -> Int {
        let fm = FileManager.default
        var ok = 0
        FileWalker.walk(url) { f in
            let unlockOK = (try? fm.setAttributes([.immutable: false], ofItemAtPath: f.path)) != nil
            var chmodOK = false
            if let mode = ((try? fm.attributesOfItem(atPath: f.path))?[.posixPermissions] as? NSNumber)?.int16Value {
                chmodOK = (try? fm.setAttributes([.posixPermissions: NSNumber(value: mode | 0o200)], ofItemAtPath: f.path)) != nil
            }
            if unlockOK && chmodOK { ok += 1 }
            return true
        }
        return ok
    }
}
