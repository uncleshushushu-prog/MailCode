//
//  EmailMessage.swift
//  MailCode
//
//  Created by MailCode contributors on 2026/6/2.
//

import Foundation

struct EmailMessage: Equatable {
    var uid: UInt64
    var sender: String
    var subject: String
    var receivedAt: Date
    var hasParsedReceivedAt: Bool
    var plainTextBody: String?
    var htmlTextBody: String?
}
