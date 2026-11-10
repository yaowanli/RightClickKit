import AppKit
import SwiftUI

/// 操作类窗口(彻底删除/批量重命名/乱码修复)的宿主,持有引用防释放。
/// 按 action(以标题为键,三个调用方标题互异)去重:重复唤起复用窗口置前,不叠开。
enum ActionWindow {
    private static var alive: [String: (window: NSWindow, observer: NSObjectProtocol)] = [:]

    @discardableResult
    static func show(title: String, width: CGFloat, height: CGFloat,
                     @ViewBuilder content: () -> some View) -> NSWindow {
        if let entry = alive[title] {
            entry.window.contentView = NSHostingView(rootView: content())
            entry.window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return entry.window
        }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                         styleMask: [.titled, .closable],
                         backing: .buffered, defer: false)
        w.title = title
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: content())
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
