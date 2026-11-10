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
}
