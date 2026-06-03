//
//  UpdateManager.swift
//  MailCode
//
//  Created by Codex on 2026/6/3.
//

import Foundation
import Combine
import Sparkle

@MainActor
final class UpdateManager: NSObject, ObservableObject, SPUUpdaterDelegate {
    private static let appcastURL = "https://github.com/uncleshushushu-prog/MailCode/releases/latest/download/appcast.xml"

    private var updaterController: SPUStandardUpdaterController!

    override init() {
        super.init()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }

    var buttonTitle: String {
        "检查更新"
    }

    var currentVersionDisplay: String {
        "\(currentVersion)"
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        Self.appcastURL
    }

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知版本"
    }
}
