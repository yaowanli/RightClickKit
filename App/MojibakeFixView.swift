import SwiftUI
import AppKit
import CoreKit

struct MojibakeFixView: View {
    struct Row: Identifiable {
        let id = UUID()
        let url: URL
        let candidates: [String]
        var chosen: String
    }

    let urls: [URL]
    @State private var rows: [Row] = []
    @State private var working = false
    @State private var error: String?
    @State private var done = false
    @State private var fixedCount = 0

    static func show(urls: [URL]) {
        ActionWindow.show(title: "修复乱码文件名", width: 600, height: 460) {
            MojibakeFixView(urls: urls)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !rows.isEmpty && rows.allSatisfy({ $0.candidates.isEmpty }) {
                Text("未检测到可修复的编码。").foregroundColor(.secondary)
            }
            List($rows) { $row in
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.url.lastPathComponent).font(.caption).foregroundColor(.secondary).lineLimit(1)
                    if row.candidates.isEmpty {
                        Text("无可识别候选").font(.system(size: 12)).foregroundColor(.orange)
                    } else if row.candidates.count == 1 {
                        // placeholder 显示候选值本身;默认空=保持原样
                        TextField(row.candidates[0], text: $row.chosen).font(.system(size: 12))
                    } else {
                        Picker("", selection: $row.chosen) {
                            Text("保持原样").tag("")
                            ForEach(row.candidates, id: \.self) { Text($0).tag($0) }
                        }.labelsHidden().font(.system(size: 12))
                    }
                }.padding(.vertical, 2)
            }
            HStack {
                if let error { Text(error).font(.caption).foregroundColor(.red) }
                if done { Text("已修复 \(fixedCount) 项。").font(.caption).foregroundColor(.green) }
                Spacer()
                Button("取消") { closeWindow() }.keyboardShortcut(.cancelAction).disabled(working)
                Button(working ? "修复中…" : "应用") { apply() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(working || done)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16).frame(width: 600, height: 460)
        .onAppear(perform: buildRows)
    }

    private func buildRows() {
        rows = urls.map { url in
            let cands = MojibakeFixer.candidates(for: url.lastPathComponent)
            // 不预选候选:默认保持原样,须由用户逐项确认(候选顺序非置信度序)
            return Row(url: url, candidates: cands, chosen: "")
        }
    }

    private func apply() {
        let ops = rows.compactMap { row -> (URL, String)? in
            let chosen = row.chosen.trimmingCharacters(in: .whitespaces) // trim 后为空视为「保持原样」
            guard !row.candidates.isEmpty, !chosen.isEmpty,
                  chosen != row.url.lastPathComponent,
                  !chosen.contains("/"), !chosen.contains(":") else { return nil }
            return (row.url, chosen)
        }
        guard !ops.isEmpty else { return } // 零操作(全部保持原样)静默 no-op,不置 done 锁窗
        working = true
        error = nil
        Task.detached {
            var ok = 0
            var err: String?
            for (url, newName) in ops {
                do {
                    try FileManager.default.moveItem(
                        at: url,
                        to: url.deletingLastPathComponent().appendingPathComponent(newName))
                    ok += 1
                } catch { err = err ?? error.localizedDescription }
            }
            let reported = err // 落为 let 再进 MainActor.run,消除并发捕获 var 警告(Swift 6 将为错误)
            let okCount = ok
            await MainActor.run {
                working = false
                if let e = reported {
                    error = e // 失败不置 done,保留重试路径
                } else {
                    fixedCount = okCount
                    done = true
                }
            }
        }
    }
    private func closeWindow() { NSApp.keyWindow?.close() }
}
