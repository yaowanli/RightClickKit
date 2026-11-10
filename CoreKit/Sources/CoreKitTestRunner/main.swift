import Foundation

runPathUtilsTests()
runFileWalkerTests()

cleanupTempDirs()

if _failures > 0 {
    print("FAILED:\(_failures)/\(_assertions) 个断言失败")
    exit(1)
}
print("ALL TESTS PASSED (\(_testsRun) tests, \(_assertions) assertions)")
