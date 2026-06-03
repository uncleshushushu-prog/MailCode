//
//  IMAPConnection.swift
//  MailCode
//
//  Created by MailCode contributors on 2026/6/2.
//

import Foundation
import Network

actor IMAPConnection {
    private let configuration: IMAPServerConfiguration
    private var connection: NWConnection?
    private var lineBuffer = ""

    init(configuration: IMAPServerConfiguration) {
        self.configuration = configuration
    }

    func open() async throws {
        let host = NWEndpoint.Host(configuration.host)
        let port = NWEndpoint.Port(rawValue: configuration.port) ?? 993
        let parameters: NWParameters = configuration.usesTLS ? .tls : .tcp
        let connection = NWConnection(host: host, port: port, using: parameters)
        self.connection = connection

        try await withTimeout(seconds: 15) {
            try await withCheckedThrowingContinuation { continuation in
                let resumeGate = ResumeGate()
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        if resumeGate.claim() {
                            continuation.resume()
                        }
                    case .failed(let error):
                        if resumeGate.claim() {
                            continuation.resume(throwing: Self.mapNetworkError(error))
                        }
                    default:
                        break
                    }
                }

                connection.start(queue: .global(qos: .userInitiated))
            }
        }
    }

    func readGreeting() async throws -> String {
        try await readLine()
    }

    func send(command: String, tag: String) async throws -> String {
        guard let connection else {
            throw MailProviderClientError.networkUnavailable
        }

        let data = Data("\(tag) \(command)\r\n".utf8)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: Self.mapNetworkError(error))
                } else {
                    continuation.resume()
                }
            })
        }

        return try await readResponse(endingWith: tag)
    }

    func close() {
        connection?.cancel()
        connection = nil
        lineBuffer = ""
    }

    private func readResponse(endingWith tag: String) async throws -> String {
        var lines: [String] = []

        while true {
            let line = try await readLine()
            lines.append(line)

            if line.uppercased().hasPrefix(tag.uppercased() + " ") {
                return lines.joined(separator: "\n")
            }
        }
    }

    private func readLine() async throws -> String {
        while true {
            if let line = popBufferedLine() {
                return line
            }

            let chunk = try await receiveChunk()
            guard let text = String(data: chunk, encoding: .utf8) else {
                throw MailProviderClientError.underlying("Invalid IMAP response encoding.")
            }

            lineBuffer += text
        }
    }

    private func receiveChunk() async throws -> Data {
        guard let connection else {
            throw MailProviderClientError.networkUnavailable
        }

        return try await withTimeout(seconds: 15) {
            try await withCheckedThrowingContinuation { continuation in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, isComplete, error in
                    if let error {
                        continuation.resume(throwing: Self.mapNetworkError(error))
                    } else if let data, !data.isEmpty {
                        continuation.resume(returning: data)
                    } else if isComplete {
                        continuation.resume(throwing: MailProviderClientError.networkUnavailable)
                    } else {
                        continuation.resume(throwing: MailProviderClientError.timeout)
                    }
                }
            }
        }
    }

    private func popBufferedLine() -> String? {
        guard let range = lineBuffer.range(of: "\r\n") ?? lineBuffer.range(of: "\n") else {
            return nil
        }

        let line = String(lineBuffer[..<range.lowerBound])
        lineBuffer.removeSubrange(..<range.upperBound)
        return line
    }

    private func withTimeout<T>(seconds: UInt64, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                throw MailProviderClientError.timeout
            }

            guard let value = try await group.next() else {
                throw MailProviderClientError.timeout
            }

            group.cancelAll()
            return value
        }
    }

    private nonisolated static func mapNetworkError(_ error: NWError) -> MailProviderClientError {
        switch error {
        case .tls:
            .tlsFailed
        case .posix:
            .networkUnavailable
        case .dns, .wifiAware:
            .networkUnavailable
        @unknown default:
            .underlying(String(describing: error))
        }
    }
}

private final class ResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var hasResumed = false

    nonisolated init() {}

    nonisolated func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard !hasResumed else {
            return false
        }

        hasResumed = true
        return true
    }
}
