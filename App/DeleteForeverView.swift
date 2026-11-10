import SwiftUI
import AppKit

struct DeleteForeverView {
    static func show(urls: [URL]) {
        ActionWindow.show(title: "彻底删除", width: 420, height: 200) {
            Text("待实现").padding()
        }
    }
}
