import Foundation

public enum MojibakeFixer {
    private static let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
        CFStringEncoding(UInt32(CFStringEncodings.GB_18030_2000.rawValue))))
    private static let big5 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
        CFStringEncoding(UInt32(CFStringEncodings.big5.rawValue))))

    private static let intermediates: [String.Encoding] = [.isoLatin1, .windowsCP1252, .macOSRoman]
    private static let targets: [String.Encoding] = [.utf8, gb18030, big5]

    /// 返回去重后的修复候选;顺序为枚举序(单字节中间编码在前、.utf8 目标在前),
    /// 不是严格置信度排序——首个候选不一定正确,UI 不得预选,须由用户确认。
    /// 不可修复或无候选时返回 []
    public static func candidates(for name: String) -> [String] {
        guard !name.contains("\u{FFFD}") else { return [] }
        var seen: Set<String> = [name]
        var out: [String] = []
        for inter in intermediates {
            guard let raw = name.data(using: inter, allowLossyConversion: false) else { continue }
            for target in targets {
                guard let fixed = String(data: raw, encoding: target),
                      fixed != name, looksCJK(fixed), seen.insert(fixed).inserted else { continue }
                out.append(fixed)
            }
        }
        return out
    }

    private static func looksCJK(_ s: String) -> Bool {
        s.unicodeScalars.contains {
            (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value)
        }
    }
}
