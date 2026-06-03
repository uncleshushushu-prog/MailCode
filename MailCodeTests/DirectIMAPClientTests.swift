//
//  DirectIMAPClientTests.swift
//  MailCodeTests
//
//  Created by MailCode contributors on 2026/6/2.
//

import XCTest
@testable import MailCode

final class DirectIMAPClientTests: XCTestCase {
    func testProviderIMAPConfigurationsMatchMVPProviders() {
        XCTAssertEqual(EmailProvider.qq.imapConfiguration, IMAPServerConfiguration(host: "imap.qq.com", port: 993, usesTLS: true))
        XCTAssertEqual(EmailProvider.netease163.imapConfiguration, IMAPServerConfiguration(host: "imap.163.com", port: 993, usesTLS: true))
        XCTAssertEqual(EmailProvider.gmail.imapConfiguration, IMAPServerConfiguration(host: "imap.gmail.com", port: 993, usesTLS: true))
        XCTAssertNil(EmailProvider.custom.imapConfiguration)
    }

    func testIMAPQuotedStringEscapesSensitiveCharacters() {
        XCTAssertEqual(IMAPCommand.quote(#"a\b"c"#), #""a\\b\"c""#)
        XCTAssertEqual(IMAPCommand.quote("line1\nline2\r"), #""line1line2""#)
    }

    func testIMAPIDCommandFormatsClientFields() {
        let command = IMAPCommand.id([
            ("name", "MailCode"),
            ("version", #"1.0"beta""#),
            ("vendor", "Mail\\Code")
        ])

        XCTAssertEqual(command, #"ID ("name" "MailCode" "version" "1.0\"beta\"" "vendor" "Mail\\Code")"#)
    }

    func testParsesCheckpointFromStatusResponse() {
        let response = """
        * STATUS INBOX (MESSAGES 10 UIDNEXT 42 UIDVALIDITY 999)
        A002 OK STATUS completed
        """

        let checkpoint = IMAPResponseParser.checkpoint(
            from: response,
            recordedAt: Date(timeIntervalSince1970: 1_780_000_000)
        )

        XCTAssertEqual(checkpoint.uidNext, 42)
        XCTAssertEqual(checkpoint.uidValidity, 999)
    }

    func testParsesCheckpointFromStatusResponseWithSeparators() {
        let response = """
        * STATUS INBOX (MESSAGES 10 UIDNEXT=42 UIDVALIDITY:999)
        A002 OK STATUS completed
        """

        let checkpoint = IMAPResponseParser.checkpoint(from: response)

        XCTAssertEqual(checkpoint.uidNext, 42)
        XCTAssertEqual(checkpoint.uidValidity, 999)
    }

    func testParsesCheckpointFromExamineResponse() {
        let response = """
        * FLAGS (\\Answered \\Flagged \\Deleted \\Seen \\Draft)
        * 10 EXISTS
        * OK [UIDVALIDITY 999] UIDs valid
        * OK [UIDNEXT 42] Predicted next UID
        A002 OK [READ-ONLY] EXAMINE completed
        """

        let checkpoint = IMAPResponseParser.checkpoint(from: response)

        XCTAssertEqual(checkpoint.uidNext, 42)
        XCTAssertEqual(checkpoint.uidValidity, 999)
        XCTAssertEqual(checkpoint.searchStartUID, 42)
    }

    func testCheckpointSearchUIDPrefersLatestUID() {
        let checkpoint = MailboxCheckpoint(
            uidValidity: 999,
            latestUID: 41,
            uidNext: 50,
            recordedAt: Date(timeIntervalSince1970: 1_780_000_000)
        )

        XCTAssertEqual(checkpoint.nextSearchUID, 42)
    }

    func testCheckpointSearchUIDFallsBackToUIDNext() {
        let checkpoint = MailboxCheckpoint(
            uidValidity: 999,
            latestUID: nil,
            uidNext: 50,
            recordedAt: Date(timeIntervalSince1970: 1_780_000_000)
        )

        XCTAssertEqual(checkpoint.nextSearchUID, 50)
    }

    func testCheckpointWithoutUIDsHasNoSearchStart() {
        let checkpoint = MailboxCheckpoint(
            uidValidity: 999,
            latestUID: nil,
            uidNext: nil,
            recordedAt: Date(timeIntervalSince1970: 1_780_000_000)
        )

        XCTAssertNil(checkpoint.searchStartUID)
    }

    func testParsesSearchUIDs() {
        let response = """
        * SEARCH 42 43 99
        A003 OK SEARCH completed
        """

        XCTAssertEqual(IMAPResponseParser.searchUIDs(from: response), [42, 43, 99])
    }

    func testParsesEmailMessageFromFetchResponse() {
        let response = """
        * 1 FETCH (UID 42 BODY[HEADER.FIELDS (FROM SUBJECT DATE)] {124}
        From: Example <security@example.com>
        Subject: Your verification code
        Date: Tue, 2 Jun 2026 12:00:00 +0800

         BODY[TEXT] {64}
        Your verification code is 123456. It expires in 5 minutes.
        )
        A004 OK FETCH completed
        """

        let message = IMAPResponseParser.emailMessage(from: response, fallbackUID: 0)

        XCTAssertEqual(message?.uid, 42)
        XCTAssertEqual(message?.sender, "Example <security@example.com>")
        XCTAssertEqual(message?.subject, "Your verification code")
        XCTAssertEqual(message?.plainTextBody, "Your verification code is 123456. It expires in 5 minutes.")
    }

    func testParsesEmailMessageInternalDateWhenHeaderDateIsUnsupported() {
        let response = """
        * 1 FETCH (UID 42 INTERNALDATE "02-Jun-2026 12:00:00 +0800" BODY[HEADER.FIELDS (FROM SUBJECT DATE)] {124}
        From: Example <security@example.com>
        Subject: Your verification code
        Date: unsupported date

         BODY[TEXT] {64}
        Your verification code is 123456. It expires in 5 minutes.
        )
        A004 OK FETCH completed
        """

        let message = IMAPResponseParser.emailMessage(from: response, fallbackUID: 0)

        XCTAssertEqual(message?.uid, 42)
        XCTAssertEqual(message?.hasParsedReceivedAt, true)
        XCTAssertEqual(message?.receivedAt, ISO8601DateFormatter().date(from: "2026-06-02T04:00:00Z"))
    }

    func testDecodesEncodedHeaderSubject() {
        let response = """
        * 1 FETCH (UID 42 BODY[HEADER.FIELDS (FROM SUBJECT DATE)] {124}
        From: Example <security@example.com>
        Subject: =?UTF-8?B?5oKo55qE6aqM6K+B56CB5pivIDEyMzQ1Ng==?=
        Date: Tue, 2 Jun 2026 12:00:00 +0800

         BODY[TEXT] {20}
        Empty body.
        )
        A004 OK FETCH completed
        """

        let message = IMAPResponseParser.emailMessage(from: response, fallbackUID: 0)

        XCTAssertEqual(message?.subject, "您的验证码是 123456")
    }

    func testDecodesQuotedPrintableBody() {
        let response = """
        * 1 FETCH (UID 42 BODY[HEADER.FIELDS (FROM SUBJECT DATE)] {124}
        From: Example <security@example.com>
        Subject: Login
        Date: Tue, 2 Jun 2026 12:00:00 +0800

         BODY[TEXT] {64}
        =E6=82=A8=E7=9A=84=E9=AA=8C=E8=AF=81=E7=A0=81=E6=98=AF 123456
        )
        A004 OK FETCH completed
        """

        let message = IMAPResponseParser.emailMessage(from: response, fallbackUID: 0)

        XCTAssertEqual(message?.plainTextBody, "您的验证码是 123456")
    }

    func testDecodesBase64MIMETextBody() {
        let response = """
        * 1 FETCH (UID 42 BODY[HEADER.FIELDS (FROM SUBJECT DATE)] {124}
        From: Example <security@example.com>
        Subject:
        Date: Tue, 2 Jun 2026 12:00:00 +0800

         BODY[TEXT] {220}
        --mailcode-boundary
        Content-Type: text/plain; charset="UTF-8"
        Content-Transfer-Encoding: base64

        5oKo55qE6aqM6K+B56CB5pivIDczNjI1Me+8jDEwIOWIhumSn+WGheacieaViOOAgg==
        --mailcode-boundary--
        )
        A004 OK FETCH completed
        """

        let message = IMAPResponseParser.emailMessage(from: response, fallbackUID: 0)

        XCTAssertEqual(message?.plainTextBody, "您的验证码是 736251，10 分钟内有效。")
    }

    func testClassifiesAuthenticationFailure() {
        let response = "A001 NO [AUTHENTICATIONFAILED] Invalid credentials"

        XCTAssertEqual(IMAPResponseParser.classifyFailure(response), .invalidCredential)
    }

    func testClassifiesNeteaseLoginPasswordFailure() {
        let response = "A001 NO LOGIN Login error or password error"

        XCTAssertEqual(IMAPResponseParser.classifyFailure(response), .invalidCredential)
    }

    func testClassifiesNeteaseUnsafeLoginFailure() {
        let response = "A004 NO SELECT Unsafe Login.Please contactkefu@188.com for help"

        XCTAssertEqual(IMAPResponseParser.classifyFailure(response), .unsafeLogin)
    }
}
