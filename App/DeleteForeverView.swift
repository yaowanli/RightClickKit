import SwiftUI
import AppKit
import CoreKit

struct DeleteForeverView: View {
    let urls: [URL]
    @State private var totalSize: Int64?
    @State private var acknowledged = false
    @State private var working = false
    @State private var error: String?
    @State private var done = false

    static func show(urls: [URL]) {
        ActionWindow.show(title: "彻底删除", width: 440, height: 260) {
            DeleteForeverView(urls: urls)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("彻底删除 \(urls.count) 个项目", systemImage: "trash.fill")
                .font(.headline).foregroundColor(.red)
            Text("路径:\(pathsSummary)")
                .font(.caption).foregroundColor(.secondary).lineLimit(3)
            Text(sizeText).foregroundColor(.secondary)
            Toggle("我了解:此操作不进废纸篓,不可恢复", isOn: $acknowledged)
                .disabled(working)
            if let error { Text(error).foregroundColor(.red).font(.caption) }
            if done { Text("已删除。").foregroundColor(.green) }
            HStack {
                Spacer()
                Button("取消") { closeWindow() }.keyboardShortcut(.cancelAction).disabled(working)
                Button(working ? "删除中…" : "彻底删除") { delete() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!acknowledged || working || done)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            }
        }
        .padding(20)
        .frame(width: 440, height: 260)
        .task { totalSize = await Task.detached { FileWalker.totalSize(of: urls) }.value }
    }

    private var pathsSummary: String {
        urls.prefix(3).map { $0.lastPathComponent }.joined(separator: "、")
            + (urls.count > 3 ? " 等" : "")
    }
    private var sizeText: String {
        guard let s = totalSize else { return "正在计算大小…" }
        return ByteCountFormatter.string(fromByteCount: s, countStyle: .file)
    }

    private func delete() {
        working = true; error = nil
        let targets = urls
        Task.detached {
            var firstError: String?
            for t in targets {
                do { try FileManager.default.removeItem(at: t) }
                catch { firstError = firstError ?? error.localizedDescription }
            }
            let reported = firstError // 落为 let 再进 MainActor.run,消除并发捕获 var 警告(Swift 6 将为错误)
            await MainActor.run {
                working = false
                if let e = reported { error = e } else { done = true }
            }
        }
    }
    private func closeWindow() { NSApp.keyWindow?.close() }
}
