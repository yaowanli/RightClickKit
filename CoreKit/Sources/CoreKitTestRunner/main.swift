import Foundation

runPathUtilsTests()
runFileWalkerTests()

if _failures > 0 {
    print("FAILED:\(_failures) 个断言失败")
    exit(1)
}
print("ALL TESTS PASSED")
