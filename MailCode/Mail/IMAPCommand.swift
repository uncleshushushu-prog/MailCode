//
//  IMAPCommand.swift
//  MailCode
//
//  Created by MailCode contributors on 2026/6/2.
//

import Foundation

enum IMAPCommand {
    static func quote(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        return "\"\(escaped)\""
    }

    static func id(_ fields: [(String, String)]) -> String {
        let payload = fields
            .flatMap { [quote($0.0), quote($0.1)] }
            .joined(separator: " ")

        return "ID (\(payload))"
    }
}
