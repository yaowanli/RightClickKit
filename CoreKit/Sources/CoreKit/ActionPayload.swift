import Foundation

public struct ActionPayload: Equatable {
    public let action: String
    public let paths: [String]

    public init(action: String, paths: [String]) {
        self.action = action
        self.paths = paths
    }

    /// rightclickkit://<action>?p=<JSON 数组,系统自动百分号编码>
    public func makeURL() -> URL? {
        guard let json = try? JSONEncoder().encode(paths),
              let str = String(data: json, encoding: .utf8) else { return nil }
        var comps = URLComponents()
        comps.scheme = "rightclickkit"
        comps.host = action
        comps.queryItems = [URLQueryItem(name: "p", value: str)]
        return comps.url
    }

    public static func parse(_ url: URL) -> ActionPayload? {
        guard url.scheme?.lowercased() == "rightclickkit",
              let host = url.host, !host.isEmpty,
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let v = comps.queryItems?.first(where: { $0.name == "p" })?.value,
              let data = v.data(using: .utf8),
              let paths = try? JSONDecoder().decode([String].self, from: data) else { return nil }
        return ActionPayload(action: host, paths: paths)
    }
}
