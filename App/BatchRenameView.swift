import SwiftUI
import AppKit

struct BatchRenameView {
    static func show(urls: [URL]) {
        ActionWindow.show(title: "批量重命名", width: 420, height: 200) {
            Text("待实现").padding()
        }
    }
}
