//
//  MailboxCheckpoint.swift
//  MailCode
//
//  Created by MailCode contributors on 2026/6/2.
//

import Foundation

struct MailboxCheckpoint: Codable, Equatable {
    var uidValidity: UInt64?
    var latestUID: UInt64?
    var uidNext: UInt64?
    var recordedAt: Date

    var searchStartUID: UInt64? {
        if let latestUID {
            return latestUID + 1
        }

        if let uidNext {
            return uidNext
        }

        return nil
    }

    var nextSearchUID: UInt64 {
        searchStartUID ?? UInt64.max
    }
}
