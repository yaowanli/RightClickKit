import Foundation
import CoreKit

func runRenameTests() {
    test("重命名:前缀加在主名前,保留扩展名") {
        let r = RenamePlanner.plan(names: ["a.txt"], rule: .prefix("项目_"))
        expectEqual(r[0].new, "项目_a.txt")
    }
    test("重命名:后缀加在扩展名前") {
        let r = RenamePlanner.plan(names: ["a.txt"], rule: .suffix("_备份"))
        expectEqual(r[0].new, "a_备份.txt")
    }
    test("重命名:序号替换主名,保留扩展名") {
        let r = RenamePlanner.plan(names: ["a.txt", "b.txt"],
                                   rule: .sequence(base: "照片", start: 1, width: 3))
        expectEqual(r[0].new, "照片001.txt")
        expectEqual(r[1].new, "照片002.txt")
    }
    test("重命名:查找替换作用于全名") {
        let r = RenamePlanner.plan(names: ["IMG_1.jpg", "IMG_2.jpg"],
                                   rule: .replace(find: "IMG", replacement: "照片"))
        expectEqual(r.map { $0.new }, ["照片_1.jpg", "照片_2.jpg"])
    }
    test("重命名:无扩展名边界") {
        let r = RenamePlanner.plan(names: ["README"], rule: .prefix("v2_"))
        expectEqual(r[0].new, "v2_README")
    }
    test("冲突检测:发现重复新名") {
        let pairs: [(old: String, new: String)] = [("a", "x"), ("b", "x")]
        expectEqual(RenamePlanner.collisions(in: pairs), ["x"])
    }
}
