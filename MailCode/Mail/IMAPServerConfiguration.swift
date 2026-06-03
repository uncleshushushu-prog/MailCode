//
//  IMAPServerConfiguration.swift
//  MailCode
//
//  Created by MailCode contributors on 2026/6/2.
//

import Foundation

struct IMAPServerConfiguration: Equatable {
    var host: String
    var port: UInt16
    var usesTLS: Bool
}
