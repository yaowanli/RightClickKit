import Foundation

// MARK: - 敏感路径准入(仅用于 rightclickkit:// 边界)
// URL 可被任意进程构造 open,主 App 可能持 FDA/辅助功能授权,不应替外部调用者
// 搬运受保护数据。扩展内的直接动作(新建/压缩/删除)来自 Finder 用户选择,不经此策略。
public enum PathPolicy {
    /// 用户主目录下的 FDA 专属目录(前缀匹配,含后代;大小写不敏感)
    private static let homeLibraryRestricted = [
        "Library/Messages", "Library/Mail", "Library/Safari", "Library/Keychains",
        "Library/Containers", "Library/Group Containers", "Library/MobileSync",
        "Library/Cookies", "Library/Metadata",
    ]
    /// 任意位置出现的路径后缀(照片/音乐/Aperture 库是受保护包)
    private static let suffixes = [".photoslibrary", ".musiclibrary", ".aplibrary", ".migratedphotolibrary"]
    /// 任意位置出现的路径分量(Time Machine 数据)
    private static let components = ["backups.backupdb", ".timemachine"]

    /// 返回被拒绝的路径;全部通过返回空数组。纯字符串判定,不做 IO
    public static func rejected(in paths: [String]) -> [String] {
        paths.filter { isRejected($0) }
    }

    static func isRejected(_ raw: String) -> Bool {
        let path = raw.lowercased()
        let home = homeDirectory().lowercased()
        for rel in homeLibraryRestricted {
            let base = "\(home)/\(rel.lowercased())"
            if path == base || path.hasPrefix("\(base)/") { return true }
        }
        for suffix in suffixes where path.hasSuffix(suffix) { return true }
        for comp in components where path.split(separator: "/").contains(Substring(comp)) { return true }
        return false
    }

    /// getpwuid 取真实 home:沙盒下 NSHomeDirectory 指容器(本策略只在主 App 用,但取法与 FeatureStore 对齐)
    private static func homeDirectory() -> String {
        guard let pw = getpwuid(getuid()) else { return NSHomeDirectory() }
        return String(cString: pw.pointee.pw_dir)
    }
}

// MARK: - 一次性 nonce 握手
// 自用工具的相称强度:UUID 单次使用 + 30 秒时效 + 0600 权限;
// 不做签名级鉴权(同用户进程本就能直接删文件,nonce 挡的是「盲构造 URL 驱动我们的授权」)。
public enum ActionAuth {
    struct Ticket: Codable { let n: String; let ts: Double }
    static let ttl: TimeInterval = 30

    /// 票据文件:与 features.json 同目录(getpwuid 真实 home,主 App 与沙盒扩展同路可达)
    public static func nonceFileURL() -> URL {
        let home: String
        if let pw = getpwuid(getuid()) { home = String(cString: pw.pointee.pw_dir) }
        else { home = NSHomeDirectory() }
        return URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent("Library/Application Support/RightClickKit/action-nonce.json")
    }

    /// 扩展侧:签发一次性 nonce(覆盖旧值,后点为准)。issuedAt 仅供测试注入
    @discardableResult
    public static func issueNonce(at file: URL = nonceFileURL(), issuedAt: Date = Date()) -> String? {
        let ticket = Ticket(n: UUID().uuidString, ts: issuedAt.timeIntervalSince1970)
        guard let data = try? JSONEncoder().encode(ticket) else { return nil }
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try data.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            return ticket.n
        } catch { return nil }
    }

    /// 主 App 侧:校验并核销。无论成败都删票据(防陈旧票据重放)
    public static func consume(_ nonce: String, at file: URL = nonceFileURL()) -> Bool {
        defer { try? FileManager.default.removeItem(at: file) }
        guard let data = try? Data(contentsOf: file),
              let ticket = try? JSONDecoder().decode(Ticket.self, from: data),
              ticket.n == nonce else { return false }
        return Date().timeIntervalSince1970 - ticket.ts <= ttl
    }
}
