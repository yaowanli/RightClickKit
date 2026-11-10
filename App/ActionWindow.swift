import AppKit
import SwiftUI

/// 操作类窗口(彻底删除/批量重命名/乱码修复)的宿主,持有引用防释放
enum ActionWindow {
    private static var alive: [ObjectIdentifier: NSWindow] = [:]

    @discardableResult
    static func show(title: String, width: CGFloat, height: CGFloat,
                     @ViewBuilder content: () -> some View) -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                         styleMask: [.titled, .closable],
                         backing: .buffered, defer: false)
        w.title = title
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: content())
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        alive[ObjectIdentifier(w)] = w
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: w, queue: .main
        ) { [weak w] _ in
            if let w { alive.removeValue(forKey: ObjectIdentifier(w)) }
        }
        return w
    }
}
