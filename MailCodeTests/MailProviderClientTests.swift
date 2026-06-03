//
//  MailProviderClientTests.swift
//  MailCodeTests
//
//  Created by MailCode contributors on 2026/6/2.
//

import XCTest
@testable import MailCode

final class MailProviderClientTests: XCTestCase {
    func testUnavailableClientReportsNotImplemented() async {
        let client = UnavailableMailProviderClient()
        let account = EmailAccount(emailAddress: "demo@gmail.com", provider: .gmail)

        do {
            try await client.testConnection(account: account, appPassword: "password")
            XCTFail("Expected unavailable client to throw")
        } catch let error as MailProviderClientError {
            XCTAssertEqual(error, .notImplemented)
            XCTAssertEqual(error.userMessage, "IMAP 连接模块尚未接入，暂时无法测试连接。")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testConnectionErrorMessagesAreUserFacing() {
        XCTAssertEqual(
            MailProviderClientError.invalidCredential.userMessage,
            "连接失败，请检查邮箱授权码是否正确。"
        )
        XCTAssertEqual(
            MailProviderClientError.imapNotEnabled.userMessage,
            "连接失败，请确认该邮箱已开启 IMAP。"
        )
        XCTAssertEqual(
            MailProviderClientError.unsafeLogin.userMessage,
            "邮箱服务商拦截了本次 IMAP 登录环境，请稍后重试，或按服务商提示联系客服处理。"
        )
        XCTAssertEqual(
            MailProviderClientError.underlying("IMAP AUTHENTICATE failed").userMessage,
            "连接失败，请检查邮箱授权码是否正确，并确认该邮箱已开启 IMAP。"
        )
    }
}
