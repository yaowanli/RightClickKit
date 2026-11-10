import Foundation

enum ExtStatus: Equatable {
    case enabled        // pluginkit 输出 "+" 前缀
    case disabled       // "-" 前缀
    case notRegistered  // 无输出(未安装/未注册)

    static func detect(bundleID: String = "com.yaowl.RightClickKit.FinderSyncExt") -> ExtStatus {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        p.arguments = ["-m", "-i", bundleID]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        try? p.run()
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        for line in out.split(separator: "\n") {
            if line.hasPrefix("+") { return .enabled }
            if line.hasPrefix("-") { return .disabled }
            if line.hasPrefix("!") { return .disabled }
        }
        return .notRegistered
    }
}
