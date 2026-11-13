import SwiftUI
import AppKit
import CoreKit

struct BatchRenameView: View {
    let urls: [URL]
    @State private var ruleIndex = 0
    @State private var prefix = ""
    @State private var suffix = ""
    @State private var seqBase = "文件"
    @State private var seqStart = "1"
    @State private var find = ""
    @State private var replaceWith = ""
    @State private var working = false
    @State private var done = false
    @State private var error: String?
    @State private var renamedCount = 0

    static func show(urls: [URL]) {
        ActionWindow.show(title: "批量重命名", width: 560, height: 480) {
            BatchRenameView(urls: urls)
        }
    }

    private var names: [String] { urls.map { $0.lastPathComponent } }

    private var rule: RenameRule {
        switch ruleIndex {
        case 0: return .prefix(prefix)
        case 1: return .suffix(suffix)
        case 2: return .sequence(base: seqBase, start: min(9_999, max(0, Int(seqStart) ?? 1)), width: 3)
        default: return .replace(find: find, replacement: replaceWith)
        }
    }

    private var planned: [(old: String, new: String)] {
        RenamePlanner.plan(names: names, rule: rule)
    }
    private var collisions: [String] { RenamePlanner.collisions(in: planned) }

    /// 批外磁盘同名冲突:新名不在本批内、但目标目录已有同名文件
    private var diskConflicts: [String] {
        guard let dir = urls.first?.deletingLastPathComponent() else { return [] }
        let olds = Set(names)
        return planned.filter { $0.old != $0.new }.map { $0.new }
            .filter { !olds.contains($0)
                && FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path) }
    }

    /// 新名可执行判定:非空且不含路径分隔符(apply 的 ops 过滤与丢项警示共用,防双写漂移)
    private func isValidNewName(_ new: String) -> Bool {
        !new.isEmpty && !new.contains("/") && !new.contains(":")
    }

    /// ops 过滤静默丢弃数:有意改名(old != new)但新名不可执行的项
    private var droppedOpsCount: Int {
        let changed = planned.filter { $0.old != $0.new }
        return changed.count - changed.filter { isValidNewName($0.new) }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("规则", selection: $ruleIndex) {
                Text("加前缀").tag(0); Text("加后缀").tag(1)
                Text("序号").tag(2); Text("查找替换").tag(3)
            }.pickerStyle(.segmented)

            switch ruleIndex {
            case 0: TextField("前缀", text: $prefix)
            case 1: TextField("后缀", text: $suffix)
            case 2: HStack { TextField("基础名", text: $seqBase)
                            TextField("起始序号", text: $seqStart).frame(width: 80) }
            default: HStack { TextField("查找", text: $find)
                             TextField("替换为", text: $replaceWith) }
            }

            if !collisions.isEmpty {
                Label("重名冲突:\(collisions.joined(separator: "、"))", systemImage: "exclamationmark.triangle")
                    .foregroundColor(.orange).font(.caption)
            }
            if !diskConflicts.isEmpty {
                Label("与文件夹中已有文件重名:\(diskConflicts.joined(separator: "、"))", systemImage: "exclamationmark.triangle").foregroundColor(.orange).font(.caption)
            }
            if droppedOpsCount > 0 {
                Label("\(droppedOpsCount) 项新名为空或含路径分隔符,已跳过", systemImage: "exclamationmark.triangle")
                    .foregroundColor(.orange).font(.caption)
            }

            List(planned, id: \.old) { p in
                HStack {
                    Text(p.old).lineLimit(1)
                    Image(systemName: "arrow.right").foregroundColor(.secondary)
                    Text(p.new).lineLimit(1).foregroundColor(.blue)
                }.font(.system(size: 12))
            }

            HStack {
                if working { ProgressView().controlSize(.small) }
                if let error { Text(error).font(.caption).foregroundColor(.red) }
                if done { StatusChip(kind: .ok, text: "已重命名 \(renamedCount) 项") }
                Spacer()
                Button("取消") { closeWindow() }.keyboardShortcut(.cancelAction).disabled(working)
                Button(working ? "重命名中…" : "应用") { apply() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(working || done || !collisions.isEmpty || !diskConflicts.isEmpty)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16).frame(width: 560, height: 480)
    }

    private func apply() {
        guard let dir = urls.first?.deletingLastPathComponent() else { return }
        let ops = planned.filter { $0.old != $0.new && isValidNewName($0.new) }
        guard !ops.isEmpty else { return } // 零操作(全部保持原样/无变化)静默 no-op,不置 done 锁窗
        working = true
        error = nil
        Task.detached {
            var ok = 0
            var err: String?
            for p in ops {
                do {
                    try FileManager.default.moveItem(
                        at: dir.appendingPathComponent(p.old),
                        to: dir.appendingPathComponent(p.new))
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
                    renamedCount = okCount
                    done = true
                    // 成功后短暂展示绿色胶囊再自动关窗(对齐彻底删除浮层);失败不关,保留重试路径
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { closeWindow() }
                }
            }
        }
    }
    private func closeWindow() { ActionWindow.close(title: "批量重命名") }
}
