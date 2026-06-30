//
//  UpdateManager.swift
//  MailCode
//
//  Created by Codex on 2026/6/3.
//

import AppKit
import Combine
import Foundation
import Sparkle

@MainActor
final class UpdateManager: NSObject, ObservableObject, SPUUpdaterDelegate {
    private static let appcastURL = "https://github.com/uncleshushushu-prog/MailCode/releases/latest/download/appcast.xml"
    private static let websiteURL = URL(string: "https://uncleshu.club/")!
    private static let noUpdateErrorCode = 1001

    private var updaterController: SPUStandardUpdaterController!
    private var hasRunStartupUpdateCheck = false

    @Published var recoveryAlert: UpdateRecoveryAlert?

    override init() {
        super.init()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        updaterController.updater.automaticallyChecksForUpdates = true
        updaterController.updater.automaticallyDownloadsUpdates = true
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

    func runStartupUpdateCheck() {
        guard !hasRunStartupUpdateCheck else {
            return
        }

        hasRunStartupUpdateCheck = true
        updaterController.updater.automaticallyChecksForUpdates = true
        updaterController.updater.automaticallyDownloadsUpdates = true
        updaterController.updater.checkForUpdatesInBackground()
    }

    func openDownloadWebsite() {
        NSWorkspace.shared.open(Self.websiteURL)
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        Self.appcastURL
    }

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        immediateInstallHandler()
        return true
    }

    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: Error) {
        showRecoveryAlert(for: error)
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        showRecoveryAlert(for: error)
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        guard updateCheck == .updatesInBackground, let error else {
            return
        }

        showRecoveryAlert(for: error)
    }

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知版本"
    }

    private func showRecoveryAlert(for error: Error) {
        let nsError = error as NSError
        guard !(nsError.domain == SUSparkleErrorDomain && nsError.code == Self.noUpdateErrorCode) else {
            return
        }

        recoveryAlert = UpdateRecoveryAlert(reason: error.localizedDescription)
    }
}

struct UpdateRecoveryAlert: Identifiable {
    let id = UUID()
    let reason: String
}
