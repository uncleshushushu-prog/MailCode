//
//  IMAPResponseParser.swift
//  MailCode
//
//  Created by MailCode contributors on 2026/6/2.
//

import Foundation

enum IMAPResponseParser {
    static func checkpoint(from response: String, recordedAt: Date = .now) -> MailboxCheckpoint {
        MailboxCheckpoint(
            uidValidity: value(named: "UIDVALIDITY", in: response),
            latestUID: nil,
            uidNext: value(named: "UIDNEXT", in: response),
            recordedAt: recordedAt
        )
    }

    static func statusIndicatesSuccess(_ response: String, tag: String) -> Bool {
        response
            .components(separatedBy: .newlines)
            .contains { line in
                line.uppercased().hasPrefix("\(tag.uppercased()) OK")
            }
    }

    static func classifyFailure(_ response: String) -> MailProviderClientError {
        let normalized = response.lowercased()

        if normalized.contains("authenticationfailed")
            || normalized.contains("authenticate failed")
            || normalized.contains("invalid credentials")
            || normalized.contains("login failed")
            || normalized.contains("login error")
            || normalized.contains("password error") {
            return .invalidCredential
        }

        if normalized.contains("imap") && normalized.contains("enable") {
            return .imapNotEnabled
        }

        if normalized.contains("unsafe login") {
            return .unsafeLogin
        }

        return .underlying(response)
    }

    static func searchUIDs(from response: String) -> [UInt64] {
        response
            .components(separatedBy: .newlines)
            .first { $0.uppercased().hasPrefix("* SEARCH") }
            .map { line in
                line
                    .dropFirst("* SEARCH".count)
                    .split(separator: " ")
                    .compactMap { UInt64($0) }
            } ?? []
    }

    static func emailMessage(from response: String, fallbackUID: UInt64) -> EmailMessage? {
        let uid = value(named: "UID", in: response) ?? fallbackUID
        let headers = headerFields(from: response)
        let parsedReceivedAt = internalDate(from: response) ?? parseDate(headers["date"])

        return EmailMessage(
            uid: uid,
            sender: headers["from"] ?? "",
            subject: headers["subject"] ?? "",
            receivedAt: parsedReceivedAt ?? .now,
            hasParsedReceivedAt: parsedReceivedAt != nil,
            plainTextBody: textBody(from: response),
            htmlTextBody: nil
        )
    }

    private static func value(named name: String, in response: String) -> UInt64? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let pattern = #"\b\#(escapedName)\b\s*[=:]?\s*(\d+)"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let nsResponse = response as NSString
        let range = NSRange(location: 0, length: nsResponse.length)

        guard
            let match = regex?.firstMatch(in: response, range: range),
            match.numberOfRanges >= 2
        else {
            return nil
        }

        return UInt64(nsResponse.substring(with: match.range(at: 1)))
    }

    private static func internalDate(from response: String) -> Date? {
        guard let regex = try? NSRegularExpression(pattern: #"INTERNALDATE\s+"([^"]+)""#, options: [.caseInsensitive]) else {
            return nil
        }

        let nsResponse = response as NSString
        let range = NSRange(location: 0, length: nsResponse.length)
        guard let match = regex.firstMatch(in: response, range: range), match.numberOfRanges >= 2 else {
            return nil
        }

        return parseDate(nsResponse.substring(with: match.range(at: 1)))
    }

    private static func headerFields(from response: String) -> [String: String] {
        var fields: [String: String] = [:]
        var currentField: String?

        for rawLine in response.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))

            if line.hasPrefix(" ") || line.hasPrefix("\t"), let currentField {
                fields[currentField, default: ""] += " " + line.trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }

            guard let colonIndex = line.firstIndex(of: ":") else {
                currentField = nil
                continue
            }

            let name = line[..<colonIndex].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard ["from", "subject", "date"].contains(name) else {
                currentField = nil
                continue
            }

            let value = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
            fields[name] = decodeHeaderValue(value)
            currentField = name
        }

        return fields
    }

    private static func textBody(from response: String) -> String? {
        guard let markerRange = response.range(of: "BODY[TEXT]", options: [.caseInsensitive]) else {
            return nil
        }

        let afterMarker = response[markerRange.upperBound...]
        guard let newlineRange = afterMarker.range(of: "\n") else {
            return nil
        }

        var body = String(afterMarker[newlineRange.upperBound...])
        if let terminatorRange = body.range(of: #"\r?\n\)\r?\n[A-Z]\d+\s+OK"#, options: [.regularExpression, .caseInsensitive]) {
            body.removeSubrange(terminatorRange.lowerBound..<body.endIndex)
        }

        return decodeTextBody(body).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeHeaderValue(_ value: String) -> String {
        let pattern = #"=\?([^?]+)\?([BQbq])\?([^?]+)\?="#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return value
        }

        let nsValue = value as NSString
        let matches = regex.matches(in: value, range: NSRange(location: 0, length: nsValue.length))
        guard !matches.isEmpty else {
            return value
        }

        var decoded = value
        for match in matches.reversed() {
            guard
                match.numberOfRanges == 4,
                let fullRange = Range(match.range(at: 0), in: decoded)
            else {
                continue
            }

            let charset = nsValue.substring(with: match.range(at: 1))
            let encoding = nsValue.substring(with: match.range(at: 2)).uppercased()
            let encodedText = nsValue.substring(with: match.range(at: 3))
            let decodedWord: String?

            if encoding == "B" {
                decodedWord = decodeBase64(encodedText, charset: charset)
            } else {
                decodedWord = decodeEncodedWordQuotedPrintable(encodedText, charset: charset)
            }

            if let decodedWord {
                decoded.replaceSubrange(fullRange, with: decodedWord)
            }
        }

        return decoded
    }

    private static func decodeBase64(_ value: String, charset: String) -> String? {
        guard let data = Data(base64Encoded: value) else {
            return nil
        }

        return string(from: data, charset: charset)
    }

    private static func decodeEncodedWordQuotedPrintable(_ value: String, charset: String) -> String? {
        let normalized = value.replacingOccurrences(of: "_", with: " ")
        let data = quotedPrintableData(from: normalized)
        return string(from: data, charset: charset)
    }

    private nonisolated static func decodeTextBody(_ value: String) -> String {
        let mimeParts = decodedMIMETextParts(from: value)
        if !mimeParts.isEmpty {
            return mimeParts.joined(separator: "\n\n")
        }

        return decodeBodyPayload(value, transferEncoding: nil, charset: "utf-8")
    }

    private nonisolated static func decodedMIMETextParts(from value: String) -> [String] {
        splitMIMEParts(value)
            .compactMap(decodedMIMETextPart)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private nonisolated static func splitMIMEParts(_ value: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\r?\n--[^\r\n]+"#) else {
            return [value]
        }

        let nsValue = value as NSString
        let range = NSRange(location: 0, length: nsValue.length)
        var parts: [String] = []
        var cursor = 0

        for match in regex.matches(in: value, range: range) {
            if match.range.location > cursor {
                parts.append(nsValue.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            }

            cursor = match.range.location + match.range.length
        }

        if cursor < nsValue.length {
            parts.append(nsValue.substring(with: NSRange(location: cursor, length: nsValue.length - cursor)))
        }

        return parts
    }

    private nonisolated static func decodedMIMETextPart(_ part: String) -> String? {
        guard let separatorRange = part.range(of: #"\r?\n\r?\n"#, options: .regularExpression) else {
            return nil
        }

        let headerBlock = String(part[..<separatorRange.lowerBound])
        let payload = String(part[separatorRange.upperBound...])
        let contentType = headerValue(named: "Content-Type", in: headerBlock)?.lowercased() ?? ""

        guard contentType.contains("text/plain") || contentType.contains("text/html") else {
            return nil
        }

        let transferEncoding = headerValue(named: "Content-Transfer-Encoding", in: headerBlock)
        let charset = charset(from: contentType) ?? "utf-8"
        return decodeBodyPayload(payload, transferEncoding: transferEncoding, charset: charset)
    }

    private nonisolated static func decodeBodyPayload(
        _ payload: String,
        transferEncoding: String?,
        charset: String
    ) -> String {
        let normalizedEncoding = transferEncoding?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch normalizedEncoding {
        case "base64":
            let encoded = payload
                .components(separatedBy: .whitespacesAndNewlines)
                .joined()

            guard let data = Data(base64Encoded: encoded) else {
                return payload
            }

            return string(from: data, charset: charset) ?? payload
        case "quoted-printable":
            return decodeQuotedPrintable(payload, charset: charset)
        default:
            if looksLikeBase64Payload(payload), let decoded = decodeLikelyBase64Payload(payload, charset: charset) {
                return decoded
            }

            return decodeQuotedPrintable(payload, charset: charset)
        }
    }

    private nonisolated static func looksLikeBase64Payload(_ payload: String) -> Bool {
        let encoded = payload
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()

        guard encoded.count >= 16, encoded.count % 4 == 0 else {
            return false
        }

        return encoded.range(of: #"^[A-Za-z0-9+/]+={0,2}$"#, options: .regularExpression) != nil
    }

    private nonisolated static func decodeLikelyBase64Payload(_ payload: String, charset: String) -> String? {
        let encoded = payload
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()

        guard let data = Data(base64Encoded: encoded) else {
            return nil
        }

        return string(from: data, charset: charset)
    }

    private nonisolated static func headerValue(named name: String, in headerBlock: String) -> String? {
        let pattern = #"(?im)^\#(NSRegularExpression.escapedPattern(for: name))\s*:\s*(.+)$"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let nsHeaderBlock = headerBlock as NSString
        let range = NSRange(location: 0, length: nsHeaderBlock.length)

        guard let match = regex?.firstMatch(in: headerBlock, range: range) else {
            return nil
        }

        return nsHeaderBlock.substring(with: match.range(at: 1))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func charset(from contentType: String) -> String? {
        let regex = try? NSRegularExpression(pattern: #"charset\s*=\s*"?([^";\s]+)"?"#, options: .caseInsensitive)
        let nsContentType = contentType as NSString
        let range = NSRange(location: 0, length: nsContentType.length)

        guard let match = regex?.firstMatch(in: contentType, range: range) else {
            return nil
        }

        return nsContentType.substring(with: match.range(at: 1))
    }

    private nonisolated static func decodeQuotedPrintable(_ value: String, charset: String = "utf-8") -> String {
        let data = quotedPrintableData(from: value)
        return string(from: data, charset: charset) ?? value
    }

    private nonisolated static func quotedPrintableData(from value: String) -> Data {
        var bytes: [UInt8] = []
        let scalars = Array(value.unicodeScalars)
        var index = 0

        while index < scalars.count {
            let scalar = scalars[index]

            if scalar == "=", index + 2 < scalars.count {
                let first = scalars[index + 1]
                let second = scalars[index + 2]

                if first == "\r", second == "\n" {
                    index += 3
                    continue
                }

                if first == "\n" {
                    index += 2
                    continue
                }

                let hex = String(first) + String(second)
                if let byte = UInt8(hex, radix: 16) {
                    bytes.append(byte)
                    index += 3
                    continue
                }
            }

            bytes.append(contentsOf: String(scalar).utf8)
            index += 1
        }

        return Data(bytes)
    }

    private nonisolated static func string(from data: Data, charset: String) -> String? {
        let normalized = charset.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        switch normalized {
        case "utf-8", "utf8":
            return String(data: data, encoding: .utf8)
        case "gb18030", "gbk", "gb2312":
            let encoding = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
            return String(data: data, encoding: String.Encoding(rawValue: encoding))
        default:
            return String(data: data, encoding: .utf8)
        }
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        let formats = [
            "EEE, d MMM yyyy HH:mm:ss Z",
            "d MMM yyyy HH:mm:ss Z",
            "EEE, d MMM yyyy HH:mm Z",
            "d MMM yyyy HH:mm Z",
            "dd-MMM-yyyy HH:mm:ss Z",
            "d-MMM-yyyy HH:mm:ss Z",
            "dd-MMM-yyyy HH:mm Z",
            "d-MMM-yyyy HH:mm Z"
        ]

        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }

        return nil
    }
}
