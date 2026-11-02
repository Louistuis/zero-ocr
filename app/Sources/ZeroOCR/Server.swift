import Foundation

/// Runs the bundled llama-server (llama.cpp, Metal) on a random localhost port with a random API key,
/// starting it on demand and stopping it after an idle period so the model costs no memory when unused.
/// The app and the `zocr` command share one server through server.json.
final class Server: @unchecked Sendable {
    static let shared = Server()

    struct State: Codable { let pid: Int32; let port: Int; let key: String }

    enum Failure: LocalizedError {
        case notInstalled, failedToStart, http(String)
        var errorDescription: String? {
            switch self {
            case .notInstalled: "The model is not downloaded yet. Open Zero OCR to finish setup."
            case .failedToStart: "The OCR engine did not start. See server.log in ~/Library/Application Support/Zero OCR."
            case .http(let m): m
            }
        }
    }

    private let lock = NSLock()
    private var process: Process?
    private var state: State?
    private var starting: Task<State, Error>?
    private var lastUse = Date()
    private var busy = 0
    private var reaper: Timer?

    /// Seconds without a read before the model is unloaded; 0 keeps it loaded.
    var keepLoaded: TimeInterval {
        let v = UserDefaults.standard.object(forKey: "keepLoaded") as? Double
        return v ?? 600
    }

    var isRunning: Bool { lock.withLock { state != nil } }
    /// Whether this process started the server (and so should stop it).
    var launchedHere: Bool { lock.withLock { process != nil } }

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 600
        c.connectionProxyDictionary = [:]   // never route localhost through a system proxy
        return URLSession(configuration: c)
    }()

    // MARK: lifecycle

    /// Starts the server if needed and returns once it answers /health. Safe to call often; callers share one start.
    @discardableResult
    func warm() async throws -> State {
        if let s = lock.withLock({ state }), await healthy(s) { return s }
        if let s = await adoptRunning() { return s }
        let task: Task<State, Error> = lock.withLock {
            if let t = starting { return t }
            let t = Task { try await self.launch() }
            starting = t
            return t
        }
        defer { lock.withLock { starting = nil } }
        return try await task.value
    }

    /// A server another Zero OCR process started (the app, when this is the command line tool).
    private func adoptRunning() async -> State? {
        guard let data = try? Data(contentsOf: Store.serverState),
              let s = try? JSONDecoder().decode(State.self, from: data), kill(s.pid, 0) == 0,
              await healthy(s) else { return nil }
        lock.withLock { state = s }
        return s
    }

    private func launch() async throws -> State {
        guard Store.ready else { throw Failure.notInstalled }
        Server.killStale()
        let exe = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/llama-server")
        let port = Server.freePort()
        let key = (0..<4).map { _ in String(UInt64.random(in: .min ... .max), radix: 36) }.joined()
        let p = Process()
        p.executableURL = exe
        p.arguments = ["-m", Store.model.url.path, "--mmproj", Store.projector.url.path,
                       "--host", "127.0.0.1", "--port", String(port), "--api-key", key,
                       "-ngl", "99", "-c", "12288", "-np", "1", "--jinja", "--no-webui",
                       "--reasoning-budget", "0", "--temp", "0"]
        FileManager.default.createFile(atPath: Store.serverLog.path, contents: nil)
        let log = try FileHandle(forWritingTo: Store.serverLog)
        p.standardOutput = log
        p.standardError = log
        p.terminationHandler = { [weak self] proc in
            guard let self else { return }
            self.lock.withLock {
                if self.process === proc { self.process = nil; self.state = nil }
            }
        }
        try p.run()
        let s = State(pid: p.processIdentifier, port: port, key: key)
        lock.withLock { process = p; state = s }
        for _ in 0..<600 {   // up to a minute; it is ready in 1 to 3 s
            if !p.isRunning { break }
            if await healthy(s) {
                if let d = try? JSONEncoder().encode(s) {
                    FileManager.default.createFile(atPath: Store.serverState.path, contents: d,
                                                   attributes: [.posixPermissions: 0o600])
                }
                touch()
                return s
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        stop()
        throw Failure.failedToStart
    }

    func stop() {
        lock.withLock {
            process?.terminate()
            process = nil
            state = nil
        }
        try? FileManager.default.removeItem(at: Store.serverState)
    }

    /// A server left behind by a crash of an earlier run.
    private static func killStale() {
        guard let data = try? Data(contentsOf: Store.serverState),
              let s = try? JSONDecoder().decode(State.self, from: data) else { return }
        var buf = [CChar](repeating: 0, count: 4096)
        if proc_pidpath(s.pid, &buf, UInt32(buf.count)) > 0, String(cString: buf).hasSuffix("/llama-server") {
            kill(s.pid, SIGTERM)
        }
        try? FileManager.default.removeItem(at: Store.serverState)
    }

    /// Unloads the model after `keepLoaded` idle seconds. Only the app runs this; the CLI stops what it started.
    func startReaper() {
        reaper?.invalidate()
        reaper = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            guard let self else { return }
            let idle = self.lock.withLock { self.busy == 0 ? Date().timeIntervalSince(self.lastUse) : 0 }
            if self.keepLoaded > 0, idle > self.keepLoaded, self.lock.withLock({ self.process != nil }) { self.stop() }
        }
    }

    func touch() { lock.withLock { lastUse = Date() } }

    private func healthy(_ s: State) async -> Bool {
        var r = URLRequest(url: URL(string: "http://127.0.0.1:\(s.port)/health")!)
        r.timeoutInterval = 1
        guard let (_, resp) = try? await Server.session.data(for: r) else { return false }
        return (resp as? HTTPURLResponse)?.statusCode == 200
    }

    private static func freePort() -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, len) }
        }
        _ = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) }
        }
        return Int(UInt16(bigEndian: addr.sin_port))
    }

    // MARK: reading

    /// Reads one prepared image, calling `onText` with the full text so far as tokens arrive.
    func read(png: Data, mode: Mode, onText: @escaping @Sendable (String) -> Void) async throws -> (String, Int) {
        let s = try await warm()
        lock.withLock { busy += 1 }
        defer { lock.withLock { busy -= 1; lastUse = Date() } }

        let body: [String: Any] = [
            "messages": [["role": "user", "content": [
                ["type": "image_url", "image_url": ["url": "data:image/png;base64," + png.base64EncodedString()]],
                ["type": "text", "text": mode.prompt],
            ]]],
            "stream": true, "temperature": 0, "max_tokens": mode.maxTokens, "cache_prompt": false,
            "chat_template_kwargs": ["enable_thinking": false],
        ]
        var r = URLRequest(url: URL(string: "http://127.0.0.1:\(s.port)/v1/chat/completions")!)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue("Bearer \(s.key)", forHTTPHeaderField: "Authorization")
        r.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, resp) = try await Server.session.bytes(for: r)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            var msg = ""
            for try await line in bytes.lines { msg += line }
            let err = (try? JSONSerialization.jsonObject(with: Data(msg.utf8)) as? [String: Any])?["error"] as? [String: Any]
            throw Failure.http(err?["message"] as? String ?? "The OCR engine returned an error.")
        }
        var text = "", tokens = 0
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = line.dropFirst(6)
            if payload == "[DONE]" { break }
            guard let obj = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any],
                  let delta = ((obj["choices"] as? [[String: Any]])?.first?["delta"] as? [String: Any])?["content"] as? String
            else { continue }
            text += delta
            tokens += 1
            onText(text)
        }
        return (text.trimmingCharacters(in: .whitespacesAndNewlines), tokens)
    }
}
