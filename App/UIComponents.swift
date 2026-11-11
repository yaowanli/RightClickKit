import SwiftUI
import CoreKit

/// 状态胶囊(FinderRight FRChip 同款):完成/警告/失败三种语义色的小标签
struct StatusChip: View {
    enum Kind { case ok, warn, fail }

    let kind: Kind
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text).lineLimit(2)
        }
        .font(.system(size: 11.5, weight: .semibold))
        .foregroundColor(fg)
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(Capsule().fill(fg.opacity(0.12)))
    }

    private var icon: String {
        switch kind {
        case .ok: return "checkmark"
        case .warn: return "exclamationmark.triangle.fill"
        case .fail: return "xmark"
        }
    }

    private var fg: Color {
        switch kind {
        case .ok: return .green
        case .warn: return .orange
        case .fail: return .red
        }
    }
}

/// 卡片外壳:圆角填充 + 细描边,内部行用 Divider 分隔(FinderRight FRCard/FRDivider 模式)
struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
    }
}

/// 权限状态行:状态图标 + 标题/说明,未授权时右侧给跳转按钮(RClick PermissionStatus 行模式)
struct PermissionRow: View {
    let icon: String
    let title: String
    let detail: String
    let granted: Bool
    var openLabel: String?
    var open: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundColor(granted ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 11.5)).foregroundColor(.secondary)
            }
            Spacer(minLength: 12)
            if !granted, let openLabel, let open {
                Button(openLabel, action: open)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

/// 功能卡片行:圆角色块图标 + 标题/说明 + 开关(FinderRight FRIconChip+FRRow 模式)
struct FeatureCardRow: View {
    let feature: Feature
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: feature.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.accentColor)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title).font(.system(size: 13, weight: .semibold))
                Text(feature.desc).font(.system(size: 11.5)).foregroundColor(.secondary)
            }
            Spacer(minLength: 12)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 48)
    }
}

