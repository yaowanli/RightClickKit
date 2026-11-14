import AppKit

/// 版本号变化时重启 Finder 一次:升级后 Finder 可能持旧扩展引用导致菜单/角标陈旧。
/// 以 CFBundleVersion 为准——日常 rebuild 不改版本号就不会触发,避免开发期反复重启 Finder
enum FinderRestarter {
    private static let key = "lastLaunchedBuildVersion"

    static func restartFinderIfNeeded() {
        let cur = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? ""
        guard !cur.isEmpty else { return }
        let prev = UserDefaults.standard.string(forKey: key)
        UserDefaults.standard.set(cur, forKey: key)
        guard let prev, prev != cur else { return } // 首次运行只记录,不重启
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        p.arguments = ["Finder"]
        try? p.run()
        NSLog("[RCK] 版本 \(prev)→\(cur),已重启 Finder 刷新扩展注册")
    }
}
