import Foundation
import Security
import Testing
@testable import PhotoTimeline

/// Sparkle fails silently or refuses to install when one of these is missing, so check the built app.
struct UpdaterConfigurationTests {
    private let info = Bundle.main.infoDictionary ?? [:]

    private func entitlement(_ key: String) -> Any? {
        guard let task = SecTaskCreateFromSelf(nil) else { return nil }
        return SecTaskCopyValueForEntitlement(task, key as CFString, nil)
    }

    @Test func feedPointsToLatestGitHubRelease() {
        #expect(info["SUFeedURL"] as? String == "https://github.com/dirkfabisch/PhotoTimeline/releases/latest/download/appcast.xml")
    }

    @Test func publicKeyIsAValidEd25519Key() throws {
        let key = try #require(info["SUPublicEDKey"] as? String)
        #expect(Data(base64Encoded: key)?.count == 32)
    }

    @Test func feedAndArchivesMustBeSigned() {
        #expect(info["SURequireSignedFeed"] as? Bool == true)
        #expect(info["SUVerifyUpdateBeforeExtraction"] as? Bool == true)
        #expect(info["SUEnableInstallerLauncherService"] as? Bool == true)
    }

    @Test func sandboxAllowsSparkle() {
        #expect(entitlement("com.apple.security.network.client") as? Bool == true)
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        // Test builds add Xcode's own services to this list, so only check that Sparkle's are there.
        let names = entitlement("com.apple.security.temporary-exception.mach-lookup.global-name") as? [String] ?? []
        #expect(names.contains("\(bundleID)-spks"))
        #expect(names.contains("\(bundleID)-spki"))
    }

    @Test func versionComesFromGit() throws {
        let build = try #require(info["CFBundleVersion"] as? String)
        #expect(Int(build).map { $0 > 1 } == true, "build number is the commit count")
        let version = try #require(info["CFBundleShortVersionString"] as? String)
        #expect(version.split(separator: ".").count == 3)
    }
}
