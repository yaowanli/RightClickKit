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

    /// 菜单图标(扩展)与设置页卡片图标共用
    public var icon: String {
        switch self {
        case .newFile: return "doc.badge.plus"
        case .newFolder: return "folder.badge.plus"
        case .folderFromName: return "doc.badge.arrow.up"
        case .cut: return "scissors"
        case .copyPath: return "link"
        case .copyName: return "doc.on.doc"
        case .compressZip: return "doc.zipper"
        case .compress7z: return "archivebox"
        case .grantWrite: return "lock.open"
        case .deleteForever: return "trash"
        case .batchRename: return "character.textbox"
        case .fixMojibake: return "wand.and.stars"
        }
    }

    /// 设置页功能卡片的一句说明
    public var desc: String {
        switch self {
        case .newFile: return "在当前位置新建 TXT/Markdown/Word/Excel/PPT 文档"
        case .newFolder: return "在当前位置新建文件夹"
        case .folderFromName: return "选中文件,以其文件名建文件夹并移入"
        case .cut: return "剪切入队列,在目标文件夹右键「粘贴(移动到此处)」"
        case .copyPath: return "复制选中项目的完整路径"
        case .copyName: return "复制选中项目的名称"
        case .compressZip: return "压缩为 zip,布局与 Finder「压缩」一致"
        case .compress7z: return "压缩为 7z(需 brew install p7zip)"
        case .grantWrite: return "递归解除锁定并给属主添加写权限"
        case .deleteForever: return "不进废纸篓直接删除,不可恢复"
        case .batchRename: return "前缀/后缀/序号/查找替换四种规则"
        case .fixMojibake: return "检测 GBK↔UTF-8 乱码文件名并逐项改名"
        }
    }
}

public enum FeatureStore {
    /// 开关存 JSON 文件而非 UserDefaults:主 App 与沙盒扩展的 suite 域相互隔离
    /// (UserDefaults(suiteName:) 在沙盒里只映射到各自容器,跨进程不可见),
    /// 文件是唯一共享通道。主 App 写,扩展每次建菜单时读(文件极小,右键场景无性能压力)
    ///
    /// 路径必须用 getpwuid 取真实 home:沙盒扩展的 homeDirectoryForCurrentUser 指向
    /// 容器 Data 目录,若用它扩展会去容器里找文件,与主 App 写的真实路径错开;
    /// getpwuid 不经沙盒重映射,两端得到同一路径
    private static let fileURL: URL = {
        guard let pw = getpwuid(getuid()) else {
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/RightClickKit/features.json")
        }
        return URL(fileURLWithPath: String(cString: pw.pointee.pw_dir), isDirectory: true)
            .appendingPathComponent("Library/Application Support/RightClickKit/features.json")
    }()

    private static func load() -> [String: Bool] {
        guard let data = try? Data(contentsOf: fileURL),
              let dict = try? JSONDecoder().decode([String: Bool].self, from: data) else { return [:] }
        return dict
    }

    /// 一次读取全部开关:menu(for:)/设置页用这个,逐项 isEnabled 会把文件 IO 乘以 12
    public static func flags() -> [Feature: Bool] {
        let dict = load()
        var out: [Feature: Bool] = [:]
        for f in Feature.allCases { out[f] = dict[f.rawValue] ?? true }
        return out
    }

    public static func isEnabled(_ f: Feature) -> Bool {
        load()[f.rawValue] ?? true
    }

    public static func setEnabled(_ f: Feature, _ on: Bool) {
        let fm = FileManager.default
        let dir = fileURL.deletingLastPathComponent()
        do { try fm.createDirectory(at: dir, withIntermediateDirectories: true) }
        catch { NSLog("[RCK] 创建配置目录失败 \(dir.path): \(error)"); return }
        var dict = load()
        dict[f.rawValue] = on
        do { try JSONEncoder().encode(dict).write(to: fileURL, options: .atomic) }
        catch { NSLog("[RCK] 写入功能开关失败 \(fileURL.path): \(error)") }
    }
}
