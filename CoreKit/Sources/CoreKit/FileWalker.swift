import Foundation

public enum FileWalker {
    /// 深度优先遍历,对每个节点(含根)调用 visit;visit 返回 false 时不进入子目录
    public static func walk(_ root: URL, visit: (URL) -> Bool) {
        guard visit(root) else { return }
        let children = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for child in children {
            let isDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir { walk(child, visit: visit) } else { _ = visit(child) }
        }
    }

    /// 递归求和;只统计文件字节,目录自身的 st_size(APFS 上 96B 级别的元数据)不计入
    public static func totalSize(of urls: [URL]) -> Int64 {
        var total: Int64 = 0
        for url in urls {
            walk(url) { f in
                let isDir = (try? f.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if !isDir, let s = try? FileManager.default.attributesOfItem(atPath: f.path)[.size] as? Int64 {
                    total += s
                }
                return true
            }
        }
        return total
    }
}
