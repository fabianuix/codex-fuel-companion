import Foundation

struct ConnectionError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Read usage on refresh; consume one reset only in response to the reset button.
struct CodexClient {
    static func executable() -> URL? {
        let candidates = [
            "/Applications/Codex.app/Contents/Resources/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            NSHomeDirectory() + "/Applications/Codex.app/Contents/Resources/codex",
            NSHomeDirectory() + "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex", "/usr/local/bin/codex"
        ] + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { String($0) + "/codex" }
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map { URL(fileURLWithPath: $0) }
    }
    static func fetch(binary: URL? = nil, timeoutSeconds: TimeInterval = 25) throws -> Snapshot {
        do {
            let data = try request(method: "account/rateLimits/read", params: nil, binary: binary, timeoutSeconds: timeoutSeconds)
            return Snapshot(limits: try JSONDecoder().decode(LimitsResponse.self, from: data))
        } catch { return Snapshot(limitsError: error.localizedDescription) }
    }
    static func fetchReasoning(binary: URL? = nil, timeoutSeconds: TimeInterval = 5) throws -> ReasoningEffort? {
        let data = try request(method: "thread/list", params: [
            "limit": 1, "sortKey": "recency_at", "sortDirection": "desc",
            "sourceKinds": ["cli", "vscode", "appServer"],
            "archived": false, "useStateDbOnly": true
        ], binary: binary, timeoutSeconds: timeoutSeconds)
        // Decode only the effort. Titles, previews and other task data are discarded.
        return try JSONDecoder().decode(ReasoningMetadataResponse.self, from: data).effort
    }
    static func consumeReset(idempotencyKey: String, binary: URL? = nil, timeoutSeconds: TimeInterval = 25) throws -> ResetOutcome {
        let data = try request(method: "account/rateLimitResetCredit/consume", params: ["idempotencyKey": idempotencyKey], binary: binary, timeoutSeconds: timeoutSeconds)
        return try JSONDecoder().decode(ResetResponse.self, from: data).outcome
    }
    private static func request(method: String, params: [String: Any]?, binary: URL?, timeoutSeconds: TimeInterval) throws -> Data {
        guard let executable = binary ?? executable() else {
            throw ConnectionError(message: "Install Codex and sign in, then refresh.")
        }
        let process = Process()
        let input = Pipe(), output = Pipe()
        process.executableURL = executable
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        // Kill a stalled read, including a child that does not respond to SIGTERM.
        let timeout = DispatchWorkItem { if process.isRunning { kill(process.processIdentifier, SIGKILL) } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds, execute: timeout)
        defer {
            timeout.cancel()
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            try? output.fileHandleForReading.close()
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
        }
        func send(_ object: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: object)
            data.append(10)
            try input.fileHandleForWriting.write(contentsOf: data)
        }
        try send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "codex_usage_menubar", "version": "1.0.0"], "capabilities": ["experimentalApi": true]]])
        var buffer = Data()
        while true {
            let chunk = output.fileHandleForReading.availableData
            guard !chunk.isEmpty else { break }
            buffer.append(chunk)
            guard buffer.count < 16_000_000 else { throw ConnectionError(message: "Codex returned an unexpectedly large response.") }
            while let newline = buffer.firstIndex(of: 10) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any], let id = object["id"] as? Int else { continue }
                if id == 1 {
                    if object["error"] != nil { throw ConnectionError(message: "This version of Codex could not connect. Update Codex and try again.") }
                    try send(["method": "initialized"])
                    var request: [String: Any] = ["id": 2, "method": method]
                    if let params { request["params"] = params }
                    try send(request)
                } else if id == 2 {
                    if let payload = object["result"] {
                        return try JSONSerialization.data(withJSONObject: payload)
                    }
                    throw ConnectionError(message: "Codex couldn’t complete the request. Check your connection and sign-in.")
                }
            }
        }
        throw ConnectionError(message: "Couldn’t reach Codex. Check your connection and sign-in, then try again.")
    }
}
