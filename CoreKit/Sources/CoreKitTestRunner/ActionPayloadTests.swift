import Foundation
import CoreKit

func runActionPayloadTests() {
    test("ActionPayload:URL 往返保留 action 与路径") {
        let p = ActionPayload(action: "batch-rename",
                              paths: ["/tmp/中 文/a.txt", "/tmp/b(1).txt"])
        let url = p.makeURL()
        expectTrue(url != nil, "makeURL 不应返回 nil")
        guard let url else { return }
        expectEqual(url.scheme, "rightclickkit")
        let back = ActionPayload.parse(url)
        expectTrue(back != nil, "parse 不应返回 nil")
        guard let back else { return }
        expectEqual(back, p)
    }
    test("ActionPayload:拒绝外来 URL") {
        expectTrue(ActionPayload.parse(URL(string: "https://example.com/p=1")!) == nil,
                   "https URL 不应被解析")
    }
    test("ActionPayload:往返保留 +&#%\" 特殊字符") {
        let p = ActionPayload(action: "copy-path",
                              paths: ["/tmp/a+b&c#d%e\"f.txt"])
        guard let url = p.makeURL() else {
            expectTrue(false, "makeURL 不应返回 nil"); return
        }
        expectEqual(ActionPayload.parse(url), p)
    }
    test("ActionPayload:空路径数组往返") {
        let p = ActionPayload(action: "cut", paths: [])
        guard let url = p.makeURL() else {
            expectTrue(false, "makeURL 不应返回 nil"); return
        }
        expectEqual(ActionPayload.parse(url), p)
    }
    test("ActionPayload:缺 p 参数判 nil") {
        expectTrue(ActionPayload.parse(URL(string: "rightclickkit://a")!) == nil,
                   "缺 p 不应被解析")
    }
}
