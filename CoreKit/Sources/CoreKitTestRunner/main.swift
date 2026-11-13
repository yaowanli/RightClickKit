import Foundation

runPathUtilsTests()
runPathPolicyTests()
runActionAuthTests()
runFileWalkerTests()
runMojibakeTests()
runRenameTests()
runActionPayloadTests()
runFileOpsTests()
runZipperTests()

cleanupTempDirs()

if _failures > 0 {
    print("FAILED:\(_failures) failures (\(_assertions) assertions run)")
    exit(1)
}
print("ALL TESTS PASSED (\(_testsRun) tests, \(_assertions) assertions)")
