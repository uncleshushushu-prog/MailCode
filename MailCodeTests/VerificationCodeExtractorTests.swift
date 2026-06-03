//
//  VerificationCodeExtractorTests.swift
//  MailCodeTests
//
//  Created by MailCode contributors on 2026/6/2.
//

import XCTest
@testable import MailCode

final class VerificationCodeExtractorTests: XCTestCase {
    private let extractor = VerificationCodeExtractor()
    private let receivedAt = Date(timeIntervalSince1970: 1_780_000_000)

    func testExtractsChineseCodeFromSubject() {
        let result = extractor.extract(from: input(subject: "您的验证码是 123456"))

        XCTAssertEqual(result?.code, "123456")
        XCTAssertGreaterThanOrEqual(result?.confidence ?? 0, 0.9)
    }

    func testExtractsEnglishCodeFromBody() {
        let result = extractor.extract(from: input(
            subject: "Login attempt",
            plainTextBody: "Your verification code is 482913. It expires in 5 minutes."
        ))

        XCTAssertEqual(result?.code, "482913")
        XCTAssertEqual(result?.expiresAt, Calendar.current.date(byAdding: .minute, value: 5, to: receivedAt))
    }

    func testExtractsCodeFromBodyWhenSubjectIsEmpty() {
        let result = extractor.extract(from: input(
            subject: "",
            plainTextBody: "您的验证码是 736251，10 分钟内有效。"
        ))

        XCTAssertEqual(result?.code, "736251")
    }

    func testExtractsCodeFromHTMLBody() {
        let result = extractor.extract(from: input(
            subject: "Security notice",
            htmlTextBody: "<html><body><p>Security code:</p><strong>774411</strong></body></html>"
        ))

        XCTAssertEqual(result?.code, "774411")
    }

    func testExtractsFullWidthNumericCode() {
        let result = extractor.extract(from: input(
            subject: "安全验证",
            plainTextBody: "您的验证码是：１２３４５６，5 分钟内有效。"
        ))

        XCTAssertEqual(result?.code, "123456")
    }

    func testExtractsSeparatedNumericCode() {
        let result = extractor.extract(from: input(
            subject: "Login code",
            plainTextBody: "Use login code 123-456 to continue."
        ))

        XCTAssertEqual(result?.code, "123456")
    }

    func testExtractsAlphaNumericCode() {
        let result = extractor.extract(from: input(
            subject: "Your verification code",
            plainTextBody: "Your verification code is AB12CD."
        ))

        XCTAssertEqual(result?.code, "AB12CD")
    }

    func testExtractsLongDeveloperPlatformCode() {
        let result = extractor.extract(from: input(
            subject: "GitHub launch code",
            plainTextBody: "Your GitHub verification code is A1B2C3D4E5."
        ))

        XCTAssertEqual(result?.code, "A1B2C3D4E5")
    }

    func testDoesNotRejectSixDigitCodeStartingWithTwenty() {
        let result = extractor.extract(from: input(
            subject: "登录验证码",
            plainTextBody: "本次验证码为 202456，请勿泄露。"
        ))

        XCTAssertEqual(result?.code, "202456")
    }

    func testRejectsOrderNumberWithoutVerificationKeyword() {
        let result = extractor.extract(from: input(
            subject: "订单 672941 已支付",
            plainTextBody: "Invoice 672941 amount $129.00, created on 2026-06-02."
        ))

        XCTAssertNil(result)
    }

    func testRejectsHTMLColorAsCode() {
        let result = extractor.extract(from: input(
            subject: "Google Account",
            htmlTextBody: """
            <html>
              <head><style>.title { color: #000000; }</style></head>
              <body><p style="color: #000000;">Security notification</p></body>
            </html>
            """
        ))

        XCTAssertNil(result)
    }

    func testRejectsAllZeroPlaceholderCode() {
        let result = extractor.extract(from: input(
            subject: "Notification",
            plainTextBody: "Reference value 000000 was included in this message."
        ))

        XCTAssertNil(result)
    }

    func testRejectsNumericCandidateWithoutVerificationKeyword() {
        let result = extractor.extract(from: input(
            subject: "Account notice",
            plainTextBody: "Reference value 482913 was included in this message."
        ))

        XCTAssertNil(result)
    }

    func testRejectsInstructionWordAfterCodeKeyword() {
        let result = extractor.extract(from: input(
            subject: "Security notice",
            plainTextBody: "Your code is valid for 10 minutes. Do not share this email."
        ))

        XCTAssertNil(result)
    }

    func testRejectsConnectorWordNearCodeKeyword() {
        let result = extractor.extract(from: input(
            subject: "Security notice",
            plainTextBody: "Sign in with this code from your email account."
        ))

        XCTAssertNil(result)
    }

    func testPrefersKeywordCodeOverAmountAndDate() {
        let result = extractor.extract(from: input(
            subject: "Payment notice",
            plainTextBody: "Amount $202606. Your OTP code is 918273 and is valid for 10 minutes."
        ))

        XCTAssertEqual(result?.code, "918273")
    }

    private func input(
        subject: String,
        plainTextBody: String? = nil,
        htmlTextBody: String? = nil
    ) -> VerificationCodeExtractor.Input {
        VerificationCodeExtractor.Input(
            sourceEmail: "test@example.com",
            sender: "Example",
            subject: subject,
            plainTextBody: plainTextBody,
            htmlTextBody: htmlTextBody,
            receivedAt: receivedAt
        )
    }
}
