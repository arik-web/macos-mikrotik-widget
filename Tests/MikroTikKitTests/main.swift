import Foundation

// Entry point for `swift run MikroTikKitTests`.
print("MikroTikKit test suite")

runRouterValueTests()
runModelParsingTests()
runTrafficRateTests()
runFormattingTests()
runSnapshotBuilderTests()
runCredentialStoreTests()
runDHCPLeaseTests()

finish()
