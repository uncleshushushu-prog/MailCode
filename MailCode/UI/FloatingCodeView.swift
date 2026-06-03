//
//  FloatingCodeView.swift
//  MailCode
//
//  Created by MailCode contributors on 2026/6/2.
//

import AppKit
import Combine
import SwiftUI

struct FloatingCodeView: View {
    let code: VerificationCode
    let onClose: () -> Void
    @AppStorage(AppPreferenceKeys.closesFloatingWindowAfterCopy) private var closesAfterCopy = false
    @State private var didCopy = false
    @State private var copyFeedbackTask: Task<Void, Never>?
    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("MailCode")
                    .font(.headline)
                Spacer()
                Text(timeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("关闭")
            }

            Button {
                copyCode()
            } label: {
                Text(code.code)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(code.sender)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(code.sourceEmail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Button {
                copyCode()
            } label: {
                Label(didCopy ? "已复制" : "复制验证码", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(18)
        .frame(width: 320, height: 228)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .onReceive(timer) { date in
            now = date
        }
        .onDisappear {
            copyFeedbackTask?.cancel()
        }
    }

    private var timeText: String {
        guard let expiresAt = code.expiresAt else {
            return "刚刚收到"
        }

        let remaining = max(0, Int(expiresAt.timeIntervalSince(now).rounded(.down)))
        guard remaining > 0 else {
            return "已过期"
        }

        let minutes = remaining / 60
        let seconds = remaining % 60
        return String(format: "%d:%02d 后过期", minutes, seconds)
    }

    private func copyCode() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(code.code, forType: .string)
        didCopy = true

        copyFeedbackTask?.cancel()
        copyFeedbackTask = Task {
            if closesAfterCopy {
                try? await Task.sleep(nanoseconds: 700_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    onClose()
                }
            } else {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    didCopy = false
                }
            }
        }
    }
}
