import Foundation
import CoreKit

func runPathPolicyTests() {
    test("PathPolicy:FDA 专属目录被拒") {
        let home = NSHomeDirectory()
        expectTrue(!PathPolicy.rejected(in: ["\(home)/Library/Messages/chat.db"]).isEmpty, "Messages 应拒")
        expectTrue(!PathPolicy.rejected(in: ["\(home)/library/mail/"]).isEmpty, "大小写不敏感")
        expectTrue(!PathPolicy.rejected(in: ["\(home)/Library/Containers/x/Data"]).isEmpty, "Containers 应拒")
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
    test("ActionAuth:错 nonce 失败且票据被清") {
        let dir = try makeTempDir()
        let file = dir.appendingPathComponent("action-nonce.json")
        _ = ActionAuth.issueNonce(at: file)
        expectTrue(!ActionAuth.consume("wrong", at: file), "错 nonce 应拒")
        expectTrue(!FileManager.default.fileExists(atPath: file.path), "失败也应清票据")
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
