//
//  MailCodeApp.swift
//  MailCode
//
//  Created by MailCode contributors on 2026/6/2.
//

import SwiftUI

@main
struct MailCodeApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
