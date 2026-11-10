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
    test("冲突检测:链式改名(新名命中他人旧名)被判冲突") {
        let r = RenamePlanner.plan(names: ["1.txt", "002.txt"],
                                   rule: .sequence(base: "", start: 2, width: 3))
        expectEqual(RenamePlanner.collisions(in: r), ["002.txt"])
    }
    test("冲突检测:identity 对不参与链式误报") {
        let pairs: [(old: String, new: String)] = [("a", "a"), ("b", "x")]
        expectEqual(RenamePlanner.collisions(in: pairs), [])
    }
    test("重命名:点开头隐藏文件按无扩展名处理") {
        let r = RenamePlanner.plan(names: [".hidden"], rule: .prefix("v2_"))
        expectEqual(r[0].new, "v2_.hidden")
    }
    test("重命名:多点文件只取最后一段扩展名") {
        let r = RenamePlanner.plan(names: ["a.b.c"], rule: .prefix("x_"))
        expectEqual(r[0].new, "x_a.b.c")
    }
    test("重命名:尾点文件名保留尾点") {
        let r = RenamePlanner.plan(names: ["name."], rule: .prefix("v2_"))
        expectEqual(r[0].new, "v2_name.")
    }
    test("重命名:空查找串为 no-op") {
        let r = RenamePlanner.plan(names: ["abc"], rule: .replace(find: "", replacement: "-"))
        expectEqual(r[0].new, "abc")
    }
}
