import Foundation
import CoreKit

func runMojibakeTests() {
    // "中文" UTF-8 字节(E4 B8 AD E6 96 87)被按 Latin-1 误读后的乱码名
    let utf8Mojibake = "\u{E4}\u{B8}\u{AD}\u{E6}\u{96}\u{87}"
    // "中文" GBK 字节(D6 D0 CE C4)被按 Latin-1 误读后的乱码名
    let gbkMojibake = "\u{D6}\u{D0}\u{CE}\u{C4}"

    test("乱码修复:UTF-8 字节被 Latin-1 误读 → 还原中文") {
        expectEqual(MojibakeFixer.candidates(for: utf8Mojibake).first ?? "", "中文")
    }
    test("乱码修复:GBK 字节被 Latin-1 误读 → 候选含中文") {
        expectTrue(MojibakeFixer.candidates(for: gbkMojibake).contains("中文"), "候选应含 中文")
    }
    test("乱码修复:正常中文名无候选") {
        expectTrue(MojibakeFixer.candidates(for: "报告.txt").isEmpty, "报告.txt 不应有候选")
    }
    test("乱码修复:纯 ASCII 名无候选") {
        expectTrue(MojibakeFixer.candidates(for: "plain.txt").isEmpty, "plain.txt 不应有候选")
    }
    test("乱码修复:含 U+FFFD 判为不可修复") {
        expectTrue(MojibakeFixer.candidates(for: "re\u{FFFD}placed.txt").isEmpty, "含替换字符应返回空")
    }
    test("乱码修复:CP1252 误读形态(en-dash)→ 首候选中文.txt") {
        let raw = Data("中文.txt".utf8)
        let form = String(data: raw, encoding: .windowsCP1252)
        expectTrue(form != nil, "CP1252 应能解码中文字节")
        guard let form else { return }
        expectEqual(MojibakeFixer.candidates(for: form).first ?? "", "中文.txt")
    }
    test("乱码修复:MacRoman 误读形态 → 候选含中文.txt") {
        let raw = Data("中文.txt".utf8)
        let form = String(data: raw, encoding: .macOSRoman)
        expectTrue(form != nil, "MacRoman 应能解码任意字节")
        guard let form else { return }
        expectTrue(MojibakeFixer.candidates(for: form).contains("中文.txt"), "候选应含 中文.txt")
    }
    test("乱码修复:空串返回空") {
        expectTrue(MojibakeFixer.candidates(for: "").isEmpty, "空串不应有候选")
    }
}
