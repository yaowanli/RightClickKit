import Foundation
import CoreKit

func runPathPolicyTests() {
    test("PathPolicy:FDA 专属目录被拒") {
        let home = NSHomeDirectory()
        expectTrue(!PathPolicy.rejected(in: ["\(home)/Library/Messages/chat.db"]).isEmpty, "Messages 应拒")
        expectTrue(!PathPolicy.rejected(in: ["\(home)/library/mail/"]).isEmpty, "大小写不敏感")
        expectTrue(!PathPolicy.rejected(in: ["\(home)/Library/Containers/x/Data"]).isEmpty, "Containers 应拒")
    }
    test("PathPolicy:非规范化路径也被拒(../、双斜杠、~ 展开)") {
        let home = NSHomeDirectory()
        expectTrue(!PathPolicy.rejected(in: ["\(home)/Desktop/../Library/Messages/chat.db"]).isEmpty, "../ 穿越应拒")
        expectTrue(!PathPolicy.rejected(in: ["\(home)//Library/Messages/chat.db"]).isEmpty, "双斜杠应拒")
        expectTrue(!PathPolicy.rejected(in: ["~/Library/Messages/chat.db"]).isEmpty, "~ 展开后应拒")
    }
    test("PathPolicy:后代目录也被拒(防打包带走)") {
        let home = NSHomeDirectory()
        expectTrue(!PathPolicy.rejected(in: ["\(home)/Library/Mail/sub/file.emlx"]).isEmpty, "后代应拒")
    }
    test("PathPolicy:库类后缀被拒") {
        expectTrue(!PathPolicy.rejected(in: ["/Users/x/Pictures/相册.photoslibrary"]).isEmpty, "photoslibrary 应拒")
    }
    test("PathPolicy:库包后代与尾斜杠也被拒(整包保护)") {
        expectTrue(!PathPolicy.rejected(in: ["/Users/x/Pictures/a.photoslibrary/database/Photos.sqlite"]).isEmpty, "包内后代应拒")
        expectTrue(!PathPolicy.rejected(in: ["/Users/x/Pictures/a.photoslibrary/"]).isEmpty, "尾斜杠应拒")
    }
    test("PathPolicy:Time Machine 组件被拒") {
        expectTrue(!PathPolicy.rejected(in: ["/Volumes/BK/backups.backupdb/Mac/Latest"]).isEmpty, "backupdb 应拒")
        expectTrue(!PathPolicy.rejected(in: ["/Volumes/.timemachine/xyz"]).isEmpty, ".timemachine 应拒")
    }
    test("PathPolicy:普通路径放行") {
        expectEqual(PathPolicy.rejected(in: ["/Users/x/Desktop/a.txt", "/tmp/b", "~/work/c.md"]), [])
        expectEqual(PathPolicy.rejected(in: []), [])
    }
}

func runActionAuthTests() {
    test("ActionAuth:签发后可核销一次,重放失败") {
        let dir = try makeTempDir()
        let file = dir.appendingPathComponent("action-nonce.json")
        guard let n = ActionAuth.issueNonce(at: file) else { expectTrue(false, "签发失败"); return }
        expectTrue(ActionAuth.consume(n, at: file), "首次核销应通过")
        expectTrue(!FileManager.default.fileExists(atPath: file.path), "核销后票据应删除")
        expectTrue(!ActionAuth.consume(n, at: file), "票据已删,重放应失败")
    }
    test("ActionAuth:错 nonce 失败且票据保留,正确 nonce 仍可核销") {
        let dir = try makeTempDir()
        let file = dir.appendingPathComponent("action-nonce.json")
        guard let n = ActionAuth.issueNonce(at: file) else { expectTrue(false, "签发失败"); return }
        expectTrue(!ActionAuth.consume("wrong", at: file), "错 nonce 应拒")
        expectTrue(FileManager.default.fileExists(atPath: file.path), "不匹配应保留票据")
        expectTrue(ActionAuth.consume(n, at: file), "保留的票据可被正确 nonce 核销(双击合并旧 URL 不毒杀新票据)")
    }
    test("ActionPayload:makeURL 带 nonce 含 n= 参数且 parse 往返不受影响") {
        let p = ActionPayload(action: "batch-rename", paths: ["/tmp/中 文/a.txt"])
        guard let url = p.makeURL(nonce: "N-abc-123") else {
            expectTrue(false, "makeURL 不应返回 nil"); return
        }
        expectTrue(url.query?.contains("n=") == true, "URL 应含 n= 参数")
        expectEqual(ActionPayload.parse(url), p)
    }
    test("ActionPayload:makeURL 不带 nonce 不含 n= 参数") {
        let p = ActionPayload(action: "rename-hint", paths: [])
        guard let url = p.makeURL() else {
            expectTrue(false, "makeURL 不应返回 nil"); return
        }
        expectTrue(url.query?.contains("n=") != true, "无 nonce 时不应含 n= 参数")
        expectEqual(ActionPayload.parse(url), p)
    }
    test("ActionAuth:过期票据失败") {
        let dir = try makeTempDir()
        let file = dir.appendingPathComponent("action-nonce.json")
        guard let n = ActionAuth.issueNonce(at: file, issuedAt: Date().addingTimeInterval(-60)) else {
            expectTrue(false, "签发失败"); return
        }
        expectTrue(!ActionAuth.consume(n, at: file), "nonce 匹配但超时应失败")
    }
    test("ActionAuth:0600 权限") {
        let dir = try makeTempDir()
        let file = dir.appendingPathComponent("action-nonce.json")
        _ = ActionAuth.issueNonce(at: file)
        let attrs = try? FileManager.default.attributesOfItem(atPath: file.path)
        expectEqual(attrs?[.posixPermissions] as? Int, 0o600)
    }
}
