import Foundation

public enum Feature: String, CaseIterable {
    case newFile = "new-file"
    case newFolder = "new-folder"
    case folderFromName = "folder-from-name"
    case cut = "cut"
    case copyPath = "copy-path"
    case copyName = "copy-name"
    case compressZip = "compress-zip"
    case compress7z = "compress-7z"
    case grantWrite = "grant-write"
    case deleteForever = "delete-forever"
    case batchRename = "batch-rename"
    case fixMojibake = "fix-mojibake"

    public var title: String {
        switch self {
        case .newFile: return "新建文件"
        case .newFolder: return "新建文件夹"
        case .folderFromName: return "使用文件名新建文件夹"
        case .cut: return "剪切"
        case .copyPath: return "拷贝路径"
        case .copyName: return "拷贝文件(夹)名称"
        case .compressZip: return "压缩为 zip"
        case .compress7z: return "压缩为 7z"
        case .grantWrite: return "授予写入权限"
        case .deleteForever: return "彻底删除"
        case .batchRename: return "批量重命名"
        case .fixMojibake: return "修复乱码文件名"
        }
    }
}

public enum FeatureStore {
    /// 主 App 与 Finder 扩展共享同一 suite(non-sandbox 下跨 bundle 可读)
    static let defaults = UserDefaults(suiteName: "com.yaowl.RightClickKit")
        ?? UserDefaults.standard

    public static func isEnabled(_ f: Feature) -> Bool {
        defaults.object(forKey: f.rawValue) as? Bool ?? true
    }
    public static func setEnabled(_ f: Feature, _ on: Bool) {
        defaults.set(on, forKey: f.rawValue)
    }
}
