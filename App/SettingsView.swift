import SwiftUI
import AppKit
import ApplicationServices
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
        }.padding(12).frame(width: 560, height: 560)
    }
}

/// 扩展与权限状态区:实时检测 Finder 扩展与辅助功能(自动重命名依赖),缺授权时给一键跳转
struct ExtensionTab: View {
    @State private var extStatus: ExtStatus = .notRegistered
    @State private var axGranted = false
    private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("扩展与权限")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.leading, 4)

                Card {
                    PermissionRow(
                        icon: "puzzlepiece.extension",
                        title: "Finder 扩展",
                        detail: extDetail,
                        granted: extStatus == .enabled,
                        openLabel: extStatus == .enabled ? nil : "打开系统设置",
                        open: { openSettings("x-apple.systempreferences:com.apple.ExtensionsPreferences") })
                    Divider().padding(.horizontal, 14)
                    PermissionRow(
                        icon: "accessibility",
                        title: "辅助功能(可选)",
                        detail: axGranted
                            ? "新建文件后将自动进入重命名"
                            : "未授权:新建文件后不会自动进入重命名,其余功能不受影响",
                        granted: axGranted,
                        openLabel: "授权",
                        open: { openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") })
                }

                Text("状态每 3 秒自动刷新;授权后无需重启 RightClickKit。")
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
                    .padding(.leading, 4)
            }
            .padding(16)
        }
        .onAppear(perform: refresh)
        .onReceive(timer) { _ in refresh() }
    }

    private var extDetail: String {
        switch extStatus {
        case .enabled: return "已启用,Finder 右键菜单可用"
        case .disabled: return "已安装但未启用,右键菜单不会出现"
        case .notRegistered: return "未检测到扩展,请先运行 build.sh 构建注册"
        }
    }

    private func refresh() {
        extStatus = ExtStatus.detect()
        axGranted = AXIsProcessTrusted()
    }

    private func openSettings(_ urlString: String) {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}

struct FeaturesTab: View {
    @State private var flags: [Feature: Bool] = Dictionary(
        uniqueKeysWithValues: Feature.allCases.map { ($0, FeatureStore.isEnabled($0)) })

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Finder 右键菜单中显示的功能")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.leading, 4)
                Card {
                    ForEach(Array(Feature.allCases.enumerated()), id: \.element.rawValue) { index, f in
                        if index > 0 { Divider().padding(.horizontal, 14) }
                        FeatureCardRow(feature: f, isOn: binding(f))
                    }
                }
                Text("开关即时生效,无需重启 Finder。")
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
                    .padding(.leading, 4)
            }
            .padding(16)
        }
    }

    private func binding(_ f: Feature) -> Binding<Bool> {
        Binding(
            get: { flags[f] ?? true },
            set: { flags[f] = $0; FeatureStore.setEnabled(f, $0) })
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
