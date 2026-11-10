import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// 最小应用菜单:没有它,程序菜单栏为空,Cmd+Q 退出失效
let mainMenu = NSMenu()
let appMenuItem = NSMenuItem()
mainMenu.addItem(appMenuItem)
let appMenu = NSMenu()
appMenu.addItem(NSMenuItem(title: "退出 RightClickKit",
                           action: #selector(NSApplication.terminate(_:)),
                           keyEquivalent: "q"))
appMenuItem.submenu = appMenu
app.mainMenu = mainMenu
app.setActivationPolicy(.regular)
app.run()
