import XCTest
@testable import CosmicCrisp

@MainActor
final class SecurityTests: XCTestCase {
    func testProfilePasscodeHashAndVerify() {
        let lock = AppLock()
        let key = "test-" + UUID().uuidString
        XCTAssertFalse(lock.hasProfilePasscode(key))
        XCTAssertTrue(lock.verifyProfilePasscode(key, passcode: "anything"))   // no passcode → open
        lock.setProfilePasscode(key, passcode: "1234")
        XCTAssertTrue(lock.hasProfilePasscode(key))
        XCTAssertTrue(lock.verifyProfilePasscode(key, passcode: "1234"))
        XCTAssertFalse(lock.verifyProfilePasscode(key, passcode: "4321"))
        lock.setProfilePasscode(key, passcode: nil)
        XCTAssertFalse(lock.hasProfilePasscode(key))
        // Salted: same passcode hashes differently with different salts.
        XCTAssertNotEqual(AppLock.hash("x", salt: [1]), AppLock.hash("x", salt: [2]))
    }

    func testLockModes() {
        let lock = AppLock()
        lock.mode = .off; lock.lockOnLaunch(); XCTAssertFalse(lock.isLocked)
        lock.mode = .onLaunch; lock.lockOnLaunch(); XCTAssertTrue(lock.isLocked)
        lock.unlockWithoutAuth(); XCTAssertFalse(lock.isLocked)
        lock.mode = .everyForeground; lock.graceSeconds = 1
        lock.didEnterBackground(); lock.willEnterForeground(); XCTAssertFalse(lock.isLocked)   // within grace
        lock.mode = .off
    }

    func testProfilesTrackedPerNodeAndProfileLock() async {
        let session = NodeSession()
        let lock = AppLock()
        session.appLock = lock
        await session.connect()
        let key = session.selfInfo!.publicKeyHex
        XCTAssertTrue(session.profiles.contains { $0.publicKeyHex == key && $0.name == "Demo Node" })
        XCTAssertFalse(session.profileLocked)
        session.setProfilePasscode("2468")
        XCTAssertTrue(lock.hasProfilePasscode(key))
        // A fresh session against the same node must be gated until the passcode is entered.
        let again = NodeSession(); again.appLock = lock
        await again.connect()
        XCTAssertTrue(again.profileLocked)
        XCTAssertFalse(again.unlockProfile(passcode: "0000"))
        XCTAssertTrue(again.unlockProfile(passcode: "2468"))
        XCTAssertFalse(again.profileLocked)
        session.setProfilePasscode(nil)
        await session.disconnect(); await again.disconnect()
    }
}
