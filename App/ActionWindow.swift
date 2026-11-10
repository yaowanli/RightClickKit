import AppKit
import SwiftUI

/// 操作类窗口(彻底删除/批量重命名/乱码修复)的宿主,持有引用防释放。
/// 按 action(以标题为键,三个调用方标题互异)去重:重复唤起复用窗口置前,不叠开。
enum ActionWindow {
    private static var alive: [String: (window: NSWindow, observer: NSObjectProtocol)] = [:]

    /// macOS 26:NSHostingView 默认按 SwiftUI 理想尺寸驱动窗口,会把窗口锁到内容固有大小(如 71x48);
    /// 关掉 sizingOptions 恢复由 contentRect 指定的窗口尺寸。新建与复用路径都必须走这里。
    private static func makeHost<Content: View>(_ content: Content) -> NSHostingView<Content> {
        let host = NSHostingView(rootView: content)
        host.sizingOptions = []
        return host
    }

    /// 弹出操作窗;同 title 复用时忽略 width/height,尺寸以首次创建为准(title 即去重键)
    @discardableResult
    static func show(title: String, width: CGFloat, height: CGFloat,
                     @ViewBuilder content: () -> some View) -> NSWindow {
        if let entry = alive[title] {
            entry.window.contentView = makeHost(content())
            entry.window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return entry.window
        }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                         styleMask: [.titled, .closable],
                         backing: .buffered, defer: false)
        w.title = title
        w.isReleasedWhenClosed = false
        w.contentView = makeHost(content())
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: w, queue: .main
        ) { [weak w, title] _ in
            guard let w, let entry = alive[title], entry.window === w else { return }
            NotificationCenter.default.removeObserver(entry.observer)
            alive.removeValue(forKey: title)
        }
        alive[title] = (w, observer)
        return w
    }
}
