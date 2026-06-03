//
//  EmailAccountStoreTests.swift
//  MailCodeTests
//
//  Created by MailCode contributors on 2026/6/2.
//

import XCTest
@testable import MailCode

final class EmailAccountStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: EmailAccountStore!

    override func setUp() {
        super.setUp()
        suiteName = "MailCodeTests.EmailAccountStore.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = EmailAccountStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        suiteName = nil
        defaults = nil
        store = nil
        super.tearDown()
    }

    func testSavesAndLoadsAccount() throws {
        let checkpoint = MailboxCheckpoint(
            uidValidity: 11,
            latestUID: 42,
            uidNext: 43,
            recordedAt: Date(timeIntervalSince1970: 1_780_000_000)
        )
        let account = EmailAccount(
            id: UUID(uuidString: "4B6904BB-800D-43C3-8C53-57010F15058A")!,
            emailAddress: "demo@gmail.com",
            provider: .gmail,
            lastCheckpoint: checkpoint,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )

        try store.save(account)

        XCTAssertEqual(store.loadAccount(), account)
    }

    func testSavesAndLoadsMultipleAccounts() throws {
        let gmail = EmailAccount(emailAddress: "demo@gmail.com", provider: .gmail)
        let qq = EmailAccount(emailAddress: "demo@qq.com", provider: .qq)

        try store.save(gmail)
        try store.save(qq)

        XCTAssertEqual(store.loadAccounts().map(\.emailAddress), ["demo@gmail.com", "demo@qq.com"])
    }

    func testSaveUpdatesExistingAccountByEmailAddress() throws {
        let original = EmailAccount(emailAddress: "demo@gmail.com", provider: .gmail)
        var updated = EmailAccount(emailAddress: "demo@gmail.com", provider: .gmail)
        updated.isEnabled = false

        try store.save(original)
        try store.save(updated)

        XCTAssertEqual(store.loadAccounts().count, 1)
        XCTAssertFalse(store.loadAccounts()[0].isEnabled)
    }

    func testMigratesLegacySingleAccount() throws {
        let legacyAccount = EmailAccount(emailAddress: "legacy@qq.com", provider: .qq)
        let data = try JSONEncoder().encode(legacyAccount)
        defaults.set(data, forKey: "mailcode.emailAccount")

        XCTAssertEqual(store.loadAccounts(), [legacyAccount])
        XCTAssertNil(defaults.data(forKey: "mailcode.emailAccount"))
    }

    func testClearRemovesSavedAccount() throws {
        try store.save(EmailAccount(emailAddress: "demo@qq.com", provider: .qq))

        store.clear()

        XCTAssertNil(store.loadAccount())
        XCTAssertEqual(store.loadAccounts(), [])
    }
}
