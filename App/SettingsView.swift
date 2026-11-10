import SwiftUI
import CoreKit

struct SettingsView: View {
    var body: some View {
        TabView {
            ExtensionTab()
                .tabItem { Label("扩展", systemImage: "puzzlepiece.extension") }
            FeaturesTab()
                .tabItem { Label("功能", systemImage: "switch.2") }
            TemplatesTab()
                .tabItem { Label("模板", systemImage: "doc") }
            AboutTab()
                .tabItem { Label("关于", systemImage: "info.circle") }
        }.padding(12).frame(width: 560, height: 540)
    }
}

struct ExtensionTab: View {
    @State private var status: ExtStatus = ExtStatus.detect()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(statusText, systemImage: statusIcon)
                .font(.title3).foregroundColor(statusColor)
            Text("首次使用:在 系统设置 → 登录项与扩展 → 扩展 → Finder 扩展 中勾选 RightClickKit。")
                .foregroundColor(.secondary)
            HStack {
                Button("刷新状态") { status = ExtStatus.detect() }
                Button("打开系统设置") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            Spacer()
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusText: String {
        switch status {
        case .enabled: return "扩展已启用"
        case .disabled: return "扩展已安装但未启用"
        case .notRegistered: return "扩展未注册,请先运行构建脚本"
        }
    }
    private var statusIcon: String {
        switch status {
        case .enabled: return "checkmark.circle.fill"
        default: return "exclamationmark.triangle.fill"
        }
    }
    private var statusColor: Color {
        status == .enabled ? .green : .orange
    }
}

struct FeaturesTab: View {
    @State private var flags: [Feature: Bool] = Dictionary(
        uniqueKeysWithValues: Feature.allCases.map { ($0, FeatureStore.isEnabled($0)) })

    var body: some View {
        List(Feature.allCases, id: \.rawValue) { f in
            Toggle(f.title, isOn: Binding(
                get: { flags[f] ?? true },
                set: { flags[f] = $0; FeatureStore.setEnabled(f, $0) }))
        }.padding(8)
    }
}

struct TemplatesTab: View {
    private let templates: [(String, String)] = [
        ("TXT 文本", "txt"), ("Markdown", "md"), ("Word 文档", "docx"),
        ("Excel 表格", "xlsx"), ("PPT 演示", "pptx"),
    ]
    var body: some View {
        List(templates, id: \.1) { t in
            HStack { Image(systemName: "doc"); Text(t.0); Spacer(); Text(".\(t.1)").foregroundColor(.secondary) }
        }.padding(8)
    }
}

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("RightClickKit").font(.title2)
            Text("版本 0.1.0 · 自用 Finder 右键增强").foregroundColor(.secondary)
            Button("退出") { NSApp.terminate(nil) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
