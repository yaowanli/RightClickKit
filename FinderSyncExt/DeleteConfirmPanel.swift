import Cocoa
import SwiftUI
import Combine
// xcodeproj 构建时 CoreKit 源文件直接编入本 module,无需 import(build.sh 仍走 SPM 动态链接)
#if !COREKIT_IN_TARGET
import CoreKit
#endif

/// 扩展进程内的「彻底删除」确认浮层(FinderRight FRDialog 同款思路):
/// 非激活面板悬浮在 Finder 之上,屏幕居中,不抢焦点、不唤起主 App;
/// 全局单实例:重复触发时替换目标并置前,不叠开多个;
/// 确认后由扩展直接删除,短暂展示「已删除」后自动关闭。
final class DeleteConfirmPanel: NSObject, NSWindowDelegate {

    final class Model: ObservableObject {
        @Published var working = false
        @Published var error: String?
        @Published var done = false
        @Published var totalSize: Int64?
        var onCancel: (() -> Void)?
        var onConfirm: (() -> Void)?
    }

    /// Esc 对应取消的 panel 子类(键盘契约:回车=删除、Esc=取消)
    private final class ConfirmPanel: NSPanel {
        var onCancel: (() -> Void)?
        override func cancelOperation(_ sender: Any?) { onCancel?() }
    }

    /// 全局单实例:同一时刻只存在一个删除确认浮层
    private static var shared: DeleteConfirmPanel?

    fileprivate static let width: CGFloat = 420

    private var urls: [URL]
    private let model = Model()
    private let panel: ConfirmPanel
    private var hosting: NSHostingView<DeleteConfirmContent>!
    private var cancellables = Set<AnyCancellable>()
    /// 代际令牌:replace(with:) 换批次时 +1,作废在途的大小计算/删除回调,防止旧批次污染新批次状态
    private var generation = 0
    /// 确认成功后的延迟自动关窗;replace 时取消,避免关掉用户刚换上的新批次确认框
    private var autoClose: DispatchWorkItem?

    static func present(urls: [URL]) {
        DispatchQueue.main.async {
            if let existing = Self.shared {
                existing.replace(with: urls)
            } else {
                let panel = DeleteConfirmPanel(urls: urls)
                Self.shared = panel
                panel.showUp()
            }
        }
    }

    private init(urls: [URL]) {
        self.urls = urls
        panel = ConfirmPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 200),
                             styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        super.init()

        rebuildContent()
        // 删除中不允许取消:后台 removeItem 循环无法中止,关掉面板只会让删除静默继续
        model.onCancel = { [weak self] in
            guard let self, !self.model.working else { return }
            self.close()
        }
        panel.onCancel = { [weak self] in
            guard let self, !self.model.working else { return }
            self.close()
        }
        model.onConfirm = { [weak self] in self?.confirm() }
        // 错误提示/完成胶囊会改变高度:内容变化后按新布局量高(底边不动,不重置用户拖放的位置)
        model.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // objectWillChange 是 willSet 时机,再让过一个 runloop 等 SwiftUI 完成重排
                DispatchQueue.main.async { self?.fitContent(keepsOrigin: true) }
            }
            .store(in: &cancellables)

        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(kind)?.isHidden = true
        }
        panel.isMovableByWindowBackground = true
        // 悬浮在访达之上;appex 常不处于激活状态,不能随「失去激活」隐藏;全屏访达所在空间也要能显示
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentView = hosting

        computeTotalSize()
    }

    /// 重复触发:替换目标文件并重置状态,复用同一个浮层
    private func replace(with newUrls: [URL]) {
        guard newUrls != urls || model.done || model.error != nil else {
            // 同一批文件且状态干净,只置前
            panel.makeKeyAndOrderFront(nil)
            return
        }
        generation += 1
        autoClose?.cancel()
        autoClose = nil
        urls = newUrls
        model.working = false
        model.error = nil
        model.done = false
        model.totalSize = nil
        rebuildContent()
        panel.contentView = hosting
        computeTotalSize()
        fitContent()
        panel.makeKeyAndOrderFront(nil)
    }

    /// urls 变化时重建 SwiftUI 内容(hosting view 持有 urls)
    private func rebuildContent() {
        hosting = NSHostingView(rootView: DeleteConfirmContent(urls: urls, model: model))
    }

    private func computeTotalSize() {
        model.totalSize = nil
        let targets = urls
        let gen = generation
        DispatchQueue.global(qos: .userInitiated).async { [weak self, model] in
            let total = FileWalker.totalSize(of: targets)
            DispatchQueue.main.async {
                guard let self, self.generation == gen else { return } // 批次已换,丢弃旧结果
                model.totalSize = total
            }
        }
    }

    private func showUp() {
        fitContent()
        panel.makeKeyAndOrderFront(nil)
        // 系统防抢焦点机制可能拦下 key 化(FRDialog 同款兜底):稍后仍未 key 则激活再取焦点
        let retry = Timer(timeInterval: 0.15, repeats: false) { [weak self] _ in
            guard let self, !self.panel.isKeyWindow else { return }
            NSApp.activate(ignoringOtherApps: true)
            self.panel.makeKeyAndOrderFront(nil)
        }
        RunLoop.main.add(retry, forMode: .common)
    }

    /// 首次展示/换批次:居中到鼠标所在屏幕(Finder 通常就在那里);
    /// 之后内容高度变化走 keepsOrigin,只调高度不重置用户拖放的位置
    private func fitContent(keepsOrigin: Bool = false) {
        guard let hosting else { return }
        let size = hosting.fittingSize
        let height = max(size.height, 140)
        var frame = panel.frameRect(forContentRect: NSRect(origin: .zero, size: NSSize(width: Self.width, height: height)))
        if keepsOrigin {
            frame.origin = panel.frame.origin
        } else {
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.visibleFrame, false) } ?? NSScreen.main
            if let visibleFrame = screen?.visibleFrame {
                frame.origin = NSPoint(x: visibleFrame.midX - frame.width / 2,
                                       y: visibleFrame.midY - frame.height / 2)
            } else {
                frame.origin = NSPoint(x: panel.frame.minX, y: panel.frame.maxY - frame.height)
            }
        }
        panel.setFrame(frame, display: true)
    }

    private func confirm() {
        guard !model.working, !model.done else { return }
        model.working = true
        model.error = nil
        let targets = urls
        let gen = generation
        DispatchQueue.global(qos: .userInitiated).async { [weak self, model] in
            var firstError: String?
            for t in targets {
                do { try FileManager.default.removeItem(at: t) }
                catch { if firstError == nil { firstError = error.localizedDescription } }
            }
            DispatchQueue.main.async {
                guard let self, self.generation == gen else { return } // 批次已换,不让旧删除写新批次状态
                model.working = false
                if let e = firstError {
                    model.error = e
                } else {
                    model.done = true
                    // 让用户瞥见「已删除」再自动关闭;换批次时取消,避免关掉新确认框
                    let work = DispatchWorkItem { [weak self] in self?.close() }
                    self.autoClose = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
                }
            }
        }
    }

    private func close() {
        autoClose?.cancel()
        autoClose = nil
        panel.orderOut(nil)
        panel.close()
    }

    func windowWillClose(_ notification: Notification) {
        if Self.shared === self { Self.shared = nil }
    }
}

private struct DeleteConfirmContent: View {
    let urls: [URL]
    @ObservedObject var model: DeleteConfirmPanel.Model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.red)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.red.opacity(0.12)))
                Text("彻底删除 \(urls.count) 个项目")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(2)
                Spacer(minLength: 8)
                // 来源标:浮层出现在 Finder 之上,标明是谁弹出的
                HStack(spacing: 4) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 14, height: 14)
                    Text("RightClickKit")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Text("路径:\(pathsSummary)")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(3)

            Text(sizeText)
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            Label("此操作不进废纸篓,删除后不可恢复", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(.red)

            if let error = model.error {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.done {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                    Text("已删除")
                }
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(.green)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.green.opacity(0.12)))
            }

            HStack(spacing: 8) {
                if model.working { ProgressView().controlSize(.small) }
                Spacer(minLength: 0)
                Button("取消") { model.onCancel?() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.working)
                Button(model.working ? "删除中…" : "彻底删除") { model.onConfirm?() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(model.working || model.done)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 16)
        .frame(width: DeleteConfirmPanel.width, alignment: .leading)
    }

    private var pathsSummary: String {
        urls.prefix(3).map { $0.lastPathComponent }.joined(separator: "、")
            + (urls.count > 3 ? " 等" : "")
    }

    private var sizeText: String {
        guard let s = model.totalSize else { return "正在计算大小…" }
        return ByteCountFormatter.string(fromByteCount: s, countStyle: .file)
    }
}
