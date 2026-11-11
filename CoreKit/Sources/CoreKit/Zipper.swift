import Foundation

/// zip / 7z 压缩,同步执行。扩展(COREKIT_IN_TARGET 编入)与主 App 共用。
/// zip 根布局与 Finder「压缩」对齐:单文件直接落根、单文件夹保留一层、多选各项平铺在根。
public enum Zipper {

    /// 压缩失败;message 可直接进通知
    public struct Failure: Error {
        public let message: String
        public init(_ message: String) { self.message = message }
    }

    public static func zip(items: [URL]) -> Result<URL, Failure> {
        guard let first = items.first else { return .failure(Failure("没有可压缩的项目")) }
        let fm = FileManager.default
        let dir = first.deletingLastPathComponent()
        // 先压到唯一临时名:正式名若在压缩开始前定好,大文件压缩期间出现的同名 zip
        // 会被 ditto 静默覆盖;完成后(查重窗口缩到瞬间)再挑正式名改名
        let tmpOut = dir.appendingPathComponent(".rck-zip-\(UUID().uuidString).zip")
        defer { try? fm.removeItem(at: tmpOut) }
        let error: String?
        if items.count == 1 {
            // 单文件不能加 --keepParent(实测会把父文件夹名带进 zip 根);单目录才保留一层
            var isDir: ObjCBool = false
            var args = ["-c", "-k", "--sequesterRsrc"]
            if fm.fileExists(atPath: first.path, isDirectory: &isDir), isDir.boolValue {
                args.append("--keepParent")
            }
            args += [first.path, tmpOut.path]
            error = runDitto(args)
        } else {
            error = zipMany(items, to: tmpOut)
        }
        if let error { return .failure(Failure(error)) }
        let out = dir.appendingPathComponent(
            PathUtils.uniqueName(in: dir, base: baseName(first), ext: "zip"))
        do {
            try fm.moveItem(at: tmpOut, to: out)
        } catch {
            return .failure(Failure("zip 压缩失败:\(error.localizedDescription)"))
        }
        return .success(out)
    }

    /// 多选:ditto -c 只接受单源,先聚合到同目录暂存目录再压。
    /// 暂存目录的生命周期必须整体包在函数作用域里 —— 曾把 defer 写在 if/else 块里,
    /// 块退出(ditto 还没运行)就把暂存删了,ditto 报 "Cannot get the real path"
    private static func zipMany(_ items: [URL], to tmpOut: URL) -> String? {
        let fm = FileManager.default
        var seen = Set<String>()
        for item in items where !seen.insert(item.lastPathComponent).inserted {
            return "所选项目中有重名「\(item.lastPathComponent)」,无法压缩到同一个 zip"
        }
        let stage = tmpOut.deletingLastPathComponent()
            .appendingPathComponent(".rck-stage-\(UUID().uuidString)")
        do {
            try fm.createDirectory(at: stage, withIntermediateDirectories: false)
        } catch {
            return "zip 压缩失败:\(error.localizedDescription)"
        }
        defer { try? fm.removeItem(at: stage) }
        for url in items {
            let target = stage.appendingPathComponent(url.lastPathComponent)
            // cp -cR 在 APFS 上是零开销克隆,失败(非 APFS 卷)再退回普通复制
            let cp = runTool(executable: "/bin/cp", arguments: ["-cR", url.path, target.path])
            if cp == nil || cp!.status != 0 {
                try? fm.removeItem(at: target)
                do { try fm.copyItem(at: url, to: target) } catch {
                    return "zip 压缩失败:\(error.localizedDescription)"
                }
            }
        }
        return runDitto(["-c", "-k", "--sequesterRsrc", stage.path, tmpOut.path])
    }

    private static func runDitto(_ args: [String]) -> String? {
        guard let result = runTool(executable: "/usr/bin/ditto", arguments: args) else {
            return "zip 压缩失败:无法启动 ditto"
        }
        guard result.status == 0 else {
            let detail = result.stderr.isEmpty ? "" : ":\(result.stderr.prefix(200))"
            return "zip 压缩失败(退出码 \(result.status))\(detail)"
        }
        return nil
    }

    /// 7z 压缩。toolPath 来自 locate7z();未安装时调用方先用 locate7z 判空给 brew 提示。
    /// 已知限制:多选跨目录时相对 cwd 仅对首项目录有效。
    public static func sevenZip(items: [URL], toolPath: String) -> Result<URL, Failure> {
        guard let first = items.first else { return .failure(Failure("没有可压缩的项目")) }
        let dir = first.deletingLastPathComponent()
        let out = dir.appendingPathComponent(
            PathUtils.uniqueName(in: dir, base: baseName(first), ext: "7z"))
        // cwd 设为首项目录、参数用 lastPathComponent 相对路径(Process 直传 argv 无 shell 切分问题)
        guard let result = runTool(
            executable: toolPath,
            arguments: ["a", "-bd", out.path] + items.map { $0.lastPathComponent },
            cwd: dir.path) else {
            return .failure(Failure("7z 压缩失败:无法启动 7zz/7za"))
        }
        guard result.status == 0 else {
            try? FileManager.default.removeItem(at: out)
            let detail = result.stderr.isEmpty ? "" : ":\(result.stderr.prefix(200))"
            return .failure(Failure("7z 压缩失败(退出码 \(result.status))\(detail)"))
        }
        return .success(out)
    }

    public static func locate7z() -> String? {
        ["/opt/homebrew/bin/7zz", "/opt/homebrew/bin/7z", "/opt/homebrew/bin/7za",
         "/usr/local/bin/7zz", "/usr/local/bin/7z", "/usr/local/bin/7za"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func baseName(_ url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }

    /// 同步运行外部工具,返回退出码与 stderr 尾部;启动失败返回 nil。
    /// stdin/stdout 接 null;stderr 必须先读到 EOF 再 waitUntilExit——管道 64KB 写满后
    /// 子进程阻塞在 write、父进程阻塞在 wait,互等死锁(FinderRight ProcessRunner 同款教训)
    static func runTool(executable: String, arguments: [String], cwd: String? = nil) -> (status: Int32, stderr: String)? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments
        if let cwd { p.currentDirectoryPath = cwd }
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        let errPipe = Pipe()
        p.standardError = errPipe
        do { try p.run() } catch { return nil }
        var tail = Data()
        let reader = errPipe.fileHandleForReading
        while true {
            let chunk = reader.availableData
            if chunk.isEmpty { break }
            tail.append(chunk)
            if tail.count > 64 * 1024 { tail = Data(tail.suffix(64 * 1024)) }
        }
        p.waitUntilExit()
        let text = String(decoding: tail, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return (p.terminationStatus, text)
    }
}
