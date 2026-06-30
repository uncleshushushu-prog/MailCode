//
//  ContentView.swift
//  MailCode
//
//  Created by MailCode contributors on 2026/6/2.
//

import AppKit
import SwiftUI

private extension Color {
    static let mailCodeSurface = Color.primary.opacity(0.035)
    static let mailCodeSurfaceStrong = Color.primary.opacity(0.06)
    static let mailCodeSuccessGreen = Color(red: 0.10, green: 0.48, blue: 0.28)
    static let mailCodeBrandBlue = Color(red: 0.18, green: 0.37, blue: 0.86)
    static let mailCodeMessageBlue = Color(red: 0.28, green: 0.43, blue: 0.74)
    static let mailCodeBrandLightBlue = Color(red: 0.53, green: 0.70, blue: 1.00)
    static let mailCodeReadyBlue = Color(red: 0.22, green: 0.38, blue: 0.58)
    static let mailCodeErrorRed = Color(red: 0.68, green: 0.18, blue: 0.18)
    static let mailCodePausedOrange = Color(red: 0.72, green: 0.32, blue: 0.16)
}

enum AppPreferenceKeys {
    static let closesFloatingWindowAfterCopy = "closesFloatingWindowAfterCopy"
}

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel
    @AppStorage(AppPreferenceKeys.closesFloatingWindowAfterCopy) private var closesFloatingWindowAfterCopy = false
    @StateObject private var updateManager = UpdateManager()
    @State private var isShowingBugFeedback = false

    var body: some View {
        ZStack {
            AppBackdrop()

            VStack(alignment: .leading, spacing: 0) {
                WindowControlsReserve()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header

                        ListeningStatusView(
                            status: appModel.listeningStatus,
                            latestCode: appModel.latestCode,
                            pollingDiagnostics: appModel.pollingDiagnostics,
                            canStartListening: appModel.savedAccounts.contains(where: \.isEnabled),
                            isListening: appModel.isListening,
                            onStartListening: {
                                appModel.startListeningForVerificationCode()
                            },
                            onStopListening: {
                                appModel.stopListening()
                            }
                        )

                        Divider()

                        AccountSetupView(
                            accountDraft: $appModel.accountDraft,
                            savedAccounts: appModel.savedAccounts,
                            listeningAccountIDs: appModel.listeningAccountIDs,
                            isListening: appModel.isListening,
                            onSave: {
                                appModel.testAndSaveAccountDraft()
                            },
                            onSetEnabled: { accountID, isEnabled in
                                appModel.setAccountEnabled(accountID: accountID, isEnabled: isEnabled)
                            },
                            onEdit: { accountID in
                                appModel.prepareAccountDraftForEditing(accountID: accountID)
                            },
                            onTestConnection: { accountID in
                                appModel.testSavedAccountConnection(accountID: accountID)
                            },
                            onDelete: { accountID in
                                appModel.deleteAccount(accountID: accountID)
                            }
                        )

                        PreferencesView(
                            canResetCheckpoint: appModel.savedAccounts.contains(where: \.isEnabled) && !appModel.isListening && !appModel.listeningStatus.isBusy,
                            onResetCheckpoint: {
                                appModel.resetCheckpointToCurrentMailbox()
                            },
                            closesFloatingWindowAfterCopy: $closesFloatingWindowAfterCopy
                        )

                        if !appModel.manualReviewEmails.isEmpty {
                            ManualReviewEmailList(
                                emails: appModel.manualReviewEmails,
                                onCopy: copyManualReviewEmail,
                                onDismiss: { id in
                                    appModel.dismissManualReviewEmail(id: id)
                                }
                            )
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 10)
                    .padding(.bottom, 28)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 600, minHeight: 520)
        .task {
            updateManager.runStartupUpdateCheck()
        }
        .alert(item: $updateManager.recoveryAlert) { alert in
            Alert(
                title: Text("自动更新失败"),
                message: Text("MailCode 没能自动完成更新。你可以前往官网下载最新版本。\n\n\(alert.reason)"),
                primaryButton: .default(Text("打开官网")) {
                    updateManager.openDownloadWebsite()
                },
                secondaryButton: .cancel(Text("稍后"))
            )
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            MailCodeLogo()

            VStack(alignment: .leading, spacing: 5) {
                Text("MailCode")
                    .font(.largeTitle.bold())

                Text("监听新邮件验证码，并用悬浮窗一键复制。")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(alignment: .top, spacing: 8) {
                Button {
                    isShowingBugFeedback = true
                } label: {
                    Label("Bug 反馈", systemImage: "qrcode")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .help("打开飞书群二维码")
                .popover(isPresented: $isShowingBugFeedback, arrowEdge: .top) {
                    BugFeedbackQRCodeView()
                }

                VStack(alignment: .trailing, spacing: 4) {
                    Button {
                        updateManager.checkForUpdates()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.2.circlepath")

                            Text(updateManager.buttonTitle)
                        }
                        .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .help("检查 MailCode 更新")

                    Text(updateManager.currentVersionDisplay)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BugFeedbackQRCodeView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Bug 反馈")
                .font(.headline)

            Image("FeishuGroup")
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(width: 220, height: 220)
                .accessibilityLabel("飞书群二维码")

            Text("扫码加入飞书群反馈问题")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(width: 260)
    }
}

private struct WindowControlsReserve: View {
    var body: some View {
        HStack {
            Color.clear
                .frame(width: 88, height: 28)
                .accessibilityHidden(true)

            Spacer()
        }
        .frame(height: 30)
        .frame(maxWidth: .infinity)
    }
}

private struct AppBackdrop: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)

            Color(nsColor: .windowBackgroundColor)
                .opacity(0.54)

            LinearGradient(
                colors: [
                    Color.primary.opacity(0.045),
                    Color.clear,
                    Color.mailCodeBrandBlue.opacity(0.035)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

private struct MailCodeLogo: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.mailCodeBrandBlue,
                            Color(red: 0.08, green: 0.16, blue: 0.42)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: 4)
                .fill(.white.opacity(0.96))
                .frame(width: 25, height: 17)
                .offset(y: -2)

            Path { path in
                path.move(to: CGPoint(x: 9.5, y: 19))
                path.addLine(to: CGPoint(x: 21, y: 26))
                path.addLine(to: CGPoint(x: 32.5, y: 19))
            }
            .stroke(Color.mailCodeBrandBlue.opacity(0.78), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))

            Text("{ }")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.mailCodeBrandLightBlue)
                .offset(y: 10)
        }
        .frame(width: 42, height: 42)
        .accessibilityHidden(true)
    }
}

private struct AccountSetupView: View {
    @Binding var accountDraft: AccountDraft
    let savedAccounts: [EmailAccount]
    let listeningAccountIDs: Set<UUID>
    let isListening: Bool
    let onSave: () -> Void
    let onSetEnabled: (UUID, Bool) -> Void
    let onEdit: (UUID) -> Void
    let onTestConnection: (UUID) -> Void
    let onDelete: (UUID) -> Void
    @State private var isShowingAddAccount = false
    @State private var accountPendingDeletion: EmailAccount?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("邮箱账号")
                    .font(.headline)

                Spacer()

                Button {
                    accountDraft = AccountDraft()
                    isShowingAddAccount = true
                } label: {
                    Label("新增邮箱", systemImage: "plus")
                }
            }

            if savedAccounts.isEmpty {
                Text("还没有保存邮箱。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(savedAccounts) { account in
                        SavedAccountRow(
                            account: account,
                            statusText: rowStatusText(for: account),
                            statusTint: rowStatusTint(for: account),
                            isEnabled: Binding(
                                get: { account.isEnabled },
                                set: { onSetEnabled(account.id, $0) }
                            ),
                            onEdit: {
                                onEdit(account.id)
                                isShowingAddAccount = true
                            },
                            onTestConnection: {
                                onTestConnection(account.id)
                            },
                            onDelete: {
                                accountPendingDeletion = account
                            }
                        )

                        if account.id != savedAccounts.last?.id {
                            Divider()
                                .padding(.leading, 30)
                        }
                    }
                }
                .background(Color.mailCodeSurfaceStrong, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .sheet(isPresented: $isShowingAddAccount) {
            AddAccountSheet(
                accountDraft: $accountDraft,
                savedAccounts: savedAccounts,
                onCancel: {
                    accountDraft = AccountDraft()
                    isShowingAddAccount = false
                },
                onSave: {
                    onSave()
                    isShowingAddAccount = false
                }
            )
        }
        .alert("删除邮箱？", isPresented: isShowingDeleteConfirmation) {
            Button("取消", role: .cancel) {
                accountPendingDeletion = nil
            }

            Button("删除", role: .destructive) {
                if let account = accountPendingDeletion {
                    onDelete(account.id)
                }
                accountPendingDeletion = nil
            }
        } message: {
            Text("将删除 \(accountPendingDeletion?.emailAddress ?? "这个邮箱")，并停止它的监听。")
        }
    }

    private var isShowingDeleteConfirmation: Binding<Bool> {
        Binding(
            get: { accountPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    accountPendingDeletion = nil
                }
            }
        )
    }

    private func rowStatusText(for account: EmailAccount) -> String {
        if isAccountListening(account) {
            return "监听中"
        }

        return account.isEnabled ? "准备就绪" : "已停用"
    }

    private func rowStatusTint(for account: EmailAccount) -> Color {
        if isAccountListening(account) {
            return .mailCodeSuccessGreen
        }

        return account.isEnabled ? .mailCodeReadyBlue : .mailCodePausedOrange
    }

    private func isAccountListening(_ account: EmailAccount) -> Bool {
        account.isEnabled && (isListening || listeningAccountIDs.contains(account.id))
    }
}

private struct SavedAccountRow: View {
    let account: EmailAccount
    let statusText: String
    let statusTint: Color
    @Binding var isEnabled: Bool
    let onEdit: () -> Void
    let onTestConnection: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: account.provider.systemImageName)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(account.emailAddress)
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Circle()
                        .fill(statusTint)
                        .frame(width: 6, height: 6)

                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(statusTint)
                }
            }

            Spacer(minLength: 8)

            Button {
                isEnabled.toggle()
            } label: {
                Label(isEnabled ? "启用" : "停用", systemImage: isEnabled ? "checkmark.circle.fill" : "minus.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isEnabled ? Color.mailCodeSuccessGreen : Color.mailCodePausedOrange)
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderless)
            .help(isEnabled ? "停用邮箱" : "启用邮箱")

            Button("编辑", action: onEdit)
                .buttonStyle(.borderless)
                .help("编辑邮箱")

            Button("测试", action: onTestConnection)
                .buttonStyle(.borderless)
                .help("测试连通")

            Button("删除", role: .destructive, action: onDelete)
                .buttonStyle(.borderless)
                .help("删除邮箱")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

private struct AddAccountSheet: View {
    @Binding var accountDraft: AccountDraft
    let savedAccounts: [EmailAccount]
    let onCancel: () -> Void
    let onSave: () -> Void
    @State private var isShowingHelp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(isEditing ? "编辑邮箱" : "新增邮箱")
                    .font(.headline)

                Spacer()

                Button("帮助") {
                    isShowingHelp = true
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Picker("服务商", selection: $accountDraft.provider) {
                        ForEach(EmailProvider.selectableProviders) { provider in
                            Text(provider.displayName)
                                .tag(provider)
                        }
                    }
                    .frame(width: 168)

                    HStack(spacing: 0) {
                        TextField("邮箱用户名", text: $accountDraft.emailLocalPart)
                            .textFieldStyle(.plain)

                        Text(accountDraft.provider.emailSuffix)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Color.mailCodeSurfaceStrong, in: RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.primary.opacity(0.08))
                    }
                }

                TextField("授权码或应用专用密码", text: $accountDraft.appPassword)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(nil)
            }

            HStack {
                Spacer()

                Button("取消", action: onCancel)

                Button(savedAccounts.contains { $0.emailAddress == accountDraft.normalizedEmailAddress } ? "更新邮箱" : "添加邮箱", action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!accountDraft.canSave)
            }
        }
        .padding(20)
        .frame(width: 500)
        .sheet(isPresented: $isShowingHelp) {
            AccountSetupHelpView()
        }
    }

    private var isEditing: Bool {
        savedAccounts.contains { $0.emailAddress == accountDraft.normalizedEmailAddress }
    }
}

private struct AccountSetupHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("邮箱配置帮助")
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                HelpParagraph(
                    title: "为什么不能直接填登录密码？",
                    message: "MailCode 通过 IMAP 读取新邮件。大多数邮箱服务商不会允许第三方客户端直接使用网页登录密码，而是要求使用授权码或应用专用密码。这样即使授权码泄露，也可以单独撤销，不影响你的主账号密码。"
                )

                HelpParagraph(
                    title: "如何获取授权码？",
                    message: "进入邮箱网页端的设置，找到 POP3/IMAP/SMTP 或第三方客户端相关设置，开启 IMAP 服务后按提示生成授权码。部分邮箱会要求短信验证或安全验证。"
                )

                HelpParagraph(
                    title: "常见位置",
                    message: "163 邮箱通常在设置里的 POP3/SMTP/IMAP；QQ 邮箱通常在设置、账号、POP3/IMAP/SMTP/Exchange/CardDAV/CalDAV 服务；Gmail 需要开启两步验证后，在 Google 账号安全设置中创建应用专用密码。"
                )

                HelpParagraph(
                    title: "填什么？",
                    message: "邮箱用户名只填 @ 前面的部分；授权码一栏填写服务商生成的授权码或应用专用密码，不填写网页登录密码。"
                )
            }

            Text("所有数据本地保存，安全、私密、放心。")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.mailCodeMessageBlue)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)

            HStack {
                Spacer()

                Button("知道了") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 520)
    }
}

private struct HelpParagraph: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ListeningStatusView: View {
    let status: ListeningStatus
    let latestCode: VerificationCode?
    let pollingDiagnostics: String?
    let canStartListening: Bool
    let isListening: Bool
    let onStartListening: () -> Void
    let onStopListening: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("监听控制")
                    .font(.headline)

                Spacer()

                HStack(spacing: 6) {
                    Circle()
                        .fill(statusIndicatorColor)
                        .frame(width: 9, height: 9)

                    Text(isListening ? "运行中" : "未运行")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(statusTextColor)
                }
            }

            HStack(spacing: 12) {
                Image(systemName: status.systemImageName)
                    .font(.title)
                    .foregroundStyle(statusIconColor)
                    .frame(width: 34)

                VStack(alignment: .leading, spacing: 4) {
                    Text(status.title)
                        .font(.body.weight(.semibold))

                    Text(statusMessage)
                        .font(.subheadline.weight(isShowingStablePollingMessage ? .medium : .regular))
                        .foregroundStyle(statusMessageColor)
                }

                Spacer()

                Toggle(
                    isListening ? "关闭监听" : "开始监听",
                    isOn: Binding(
                        get: { isListening },
                        set: { shouldListen in
                            if shouldListen {
                                onStartListening()
                            } else {
                                onStopListening()
                            }
                        }
                    )
                )
                .font(.body.weight(.semibold))
                .toggleStyle(.switch)
                .disabled((!canStartListening && !isListening) || status.isBusy)
            }
            .padding(14)
            .background(Color.mailCodeSurfaceStrong, in: RoundedRectangle(cornerRadius: 8))

            if let latestCode {
                VStack(alignment: .leading, spacing: 6) {
                    Text("最近验证码")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(latestCode.code)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var statusMessage: String {
        guard let pollingDiagnostics, !pollingDiagnostics.isEmpty else {
            if isListening, case .polling = status {
                return AppModel.stablePollingMessage
            }

            return status.message
        }

        return pollingDiagnostics
    }

    private var isShowingStablePollingMessage: Bool {
        guard isListening, case .polling = status else {
            return false
        }

        return pollingDiagnostics?.isEmpty ?? true
    }

    private var statusMessageColor: Color {
        if case .failed = status {
            return .mailCodeErrorRed
        }

        return isShowingStablePollingMessage ? .mailCodeMessageBlue : .secondary
    }

    private var statusIndicatorColor: Color {
        if isListening {
            return .mailCodeSuccessGreen
        }

        if case .failed = status {
            return .mailCodeErrorRed
        }

        if canStartListening {
            return .mailCodeReadyBlue
        }

        return .secondary.opacity(0.55)
    }

    private var statusTextColor: Color {
        if case .failed = status {
            return .mailCodeErrorRed
        }

        return .primary
    }

    private var statusIconColor: Color {
        if case .failed = status {
            return .mailCodeErrorRed
        }

        return .secondary
    }
}

private struct PreferencesView: View {
    let canResetCheckpoint: Bool
    let onResetCheckpoint: () -> Void
    @Binding var closesFloatingWindowAfterCopy: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("设置与维护")
                .font(.headline)

            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("点击复制后自动关闭窗口")
                            .font(.footnote.weight(.medium))

                        Text("复制成功反馈显示后自动关闭验证码窗口。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: $closesFloatingWindowAfterCopy)
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

                Divider()
                    .padding(.leading, 10)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("重新定位监听起点")
                            .font(.footnote.weight(.medium))

                        Text("适合刚清理邮箱、刚更换授权码，或发现旧邮件反复触发时使用；会忽略当前已有邮件，只监听之后收到的新邮件。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Button("重新定位", action: onResetCheckpoint)
                        .disabled(!canResetCheckpoint)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .background(Color.mailCodeSurface, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct ManualReviewEmailList: View {
    let emails: [ManualReviewEmail]
    let onCopy: (ManualReviewEmail) -> Void
    let onDismiss: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("待人工处理")
                .font(.subheadline.weight(.semibold))

            ForEach(emails) { email in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(email.subject)
                                .font(.footnote.weight(.medium))
                                .lineLimit(1)

                            Text("\(email.sourceEmail) · \(email.sender)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Button("复制正文") {
                            onCopy(email)
                        }

                        Button("忽略") {
                            onDismiss(email.id)
                        }
                    }

                    Text(email.debugSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.mailCodeSurfaceStrong, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

private func copyManualReviewEmail(_ email: ManualReviewEmail) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(email.bodyText, forType: .string)
}
