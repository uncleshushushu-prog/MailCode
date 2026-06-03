//
//  VerificationCode.swift
//  MailCode
//
//  Created by MailCode contributors on 2026/6/2.
//

import Foundation

struct VerificationCode: Identifiable {
    let id = UUID()
    let code: String
    let sourceEmail: String
    let sender: String
    let subject: String
    let receivedAt: Date
    let confidence: Double
    let expiresAt: Date?
}
