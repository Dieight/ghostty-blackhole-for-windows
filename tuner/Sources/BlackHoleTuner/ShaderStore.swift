import AppKit
import Foundation

struct ShaderParam: Identifiable, Equatable {
    let name: String
    var value: Double
    var id: String { name }
}

/// Owns the shader file: parses the tunable block, writes nudged values back
/// (only the touched lines, atomically — claude-token.py rewrites TOKEN_LEVEL
/// in the same file live), hot-reloads Ghostty via SIGUSR2, and watches the
/// file so external edits show up in the UI.
final class ShaderStore: ObservableObject {
    @Published private(set) var params: [ShaderParam] = []
    @Published var status = "no shader loaded"
    @Published private(set) var shaderURL: URL?

    private var pending: [String: Double] = [:]
    private var lastTouched: [String: Date] = [:]
    private var flushTimer: Timer?
    private var rescanTimer: Timer?
    private var watcher: DispatchSourceFileSystemObject?

    // const float NAME = 1.2345; // comment        (the tunable block)
    // #define TOKEN_LEVEL 0.1234 // token-level    (owned by claude-token.py)
    private static let constRe = try! NSRegularExpression(
        pattern: #"^(const float\s+)(\w+)(\s*=\s*)(-?\d+\.\d+)(\s*;.*)$"#,
        options: [.anchorsMatchLines])
    private static let defineRe = try! NSRegularExpression(
        pattern: #"^(#define\s+)(TOKEN_LEVEL)(\s+)(-?\d+\.\d+)(\s*//.*)$"#,
        options: [.anchorsMatchLines])

    init() {
        if let url = Self.locateShader() {
            open(url: url)
        }
    }

    // MARK: - locating / loading

    /// Search order: explicit env var, the repo this source file lives in
    /// (right for `swift run` and the bundled .app inside the repo), then the
    /// working directory and its parent.
    static func locateShader() -> URL? {
        var candidates: [URL] = []
        if let env = ProcessInfo.processInfo.environment["BLACKHOLE_SHADER"] {
            candidates.append(URL(fileURLWithPath: env))
        }
        let source = URL(fileURLWithPath: #filePath)  // …/tuner/Sources/BlackHoleTuner/ShaderStore.swift
        candidates.append(
            source.deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("blackhole.glsl"))
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        candidates.append(cwd.appendingPathComponent("blackhole.glsl"))
        candidates.append(cwd.deletingLastPathComponent().appendingPathComponent("blackhole.glsl"))
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    func open(url: URL) {
        shaderURL = url
        params = (try? parseFile()) ?? []
        status = params.isEmpty
            ? "no tunables found in \(url.lastPathComponent)"
            : "\(params.count) params from \(url.lastPathComponent)"
        startWatching()
    }

    func chooseShader() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = []
        panel.allowsOtherFileTypes = true
        panel.canChooseDirectories = false
        panel.message = "Pick blackhole.glsl"
        if panel.runModal() == .OK, let url = panel.url {
            open(url: url)
        }
    }

    func current(_ name: String) -> Double {
        params.first { $0.name == name }?.value ?? 0
    }

    private func parseFile() throws -> [ShaderParam] {
        guard let url = shaderURL else { return [] }
        let text = try String(contentsOf: url, encoding: .utf8)
        let whole = NSRange(text.startIndex..., in: text)
        var found: [(Range<String.Index>, ShaderParam)] = []
        for re in [Self.constRe, Self.defineRe] {
            re.enumerateMatches(in: text, range: whole) { match, _, _ in
                guard let match,
                      let nameRange = Range(match.range(at: 2), in: text),
                      let valueRange = Range(match.range(at: 4), in: text),
                      let value = Double(text[valueRange])
                else { return }
                found.append((nameRange, ShaderParam(name: String(text[nameRange]), value: value)))
            }
        }
        return found.sorted { $0.0.lowerBound < $1.0.lowerBound }.map(\.1)
    }

    // MARK: - editing

    /// Slider/text edits land here; writes are debounced so a drag produces a
    /// stream of ~10 reloads per second instead of hundreds.
    func set(_ name: String, to value: Double) {
        guard let i = params.firstIndex(where: { $0.name == name }) else { return }
        guard params[i].value != value else { return }
        params[i].value = value
        pending[name] = value
        lastTouched[name] = Date()
        flushTimer?.invalidate()
        flushTimer = Timer.scheduledTimer(withTimeInterval: 0.09, repeats: false) { [weak self] _ in
            self?.flush()
        }
    }

    func apply(preset values: [String: Double]) {
        for (name, value) in values where params.contains(where: { $0.name == name }) {
            if let i = params.firstIndex(where: { $0.name == name }) {
                params[i].value = value
                pending[name] = value
                lastTouched[name] = Date()
            }
        }
        flush()
    }

    private func flush() {
        flushTimer?.invalidate()
        guard !pending.isEmpty, let url = shaderURL else { return }
        let values = pending
        pending = [:]
        do {
            // re-read fresh and substitute by name: claude-token.py rewrites
            // TOKEN_LEVEL live, and writing a stale snapshot would clobber it
            var text = try String(contentsOf: url, encoding: .utf8)
            for re in [Self.constRe, Self.defineRe] {
                let whole = NSRange(text.startIndex..., in: text)
                var edits: [(NSRange, String)] = []
                re.enumerateMatches(in: text, range: whole) { match, _, _ in
                    guard let match,
                          let nameRange = Range(match.range(at: 2), in: text),
                          let value = values[String(text[nameRange])]
                    else { return }
                    edits.append((match.range(at: 4), String(format: "%.4f", value)))
                }
                for (range, replacement) in edits.reversed() {
                    if let r = Range(range, in: text) {
                        text.replaceSubrange(r, with: replacement)
                    }
                }
            }
            try text.write(to: url, atomically: true, encoding: .utf8)
            let reloaded = reloadGhostty()
            let names = values.keys.sorted().joined(separator: ", ")
            status = reloaded
                ? "saved \(names) — Ghostty reloaded"
                : "saved \(names) — reload failed (is Ghostty running?)"
        } catch {
            status = "save failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Ghostty reload

    /// Ghostty (>= 1.2) reloads its config — including custom shaders — on
    /// SIGUSR2. PIDs come from ps, not pgrep: pgrep silently excludes its own
    /// ancestors, which bites when a tool runs inside Ghostty itself.
    @discardableResult
    func reloadGhostty() -> Bool {
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-axco", "pid,comm"]
        let pipe = Pipe()
        ps.standardOutput = pipe
        do { try ps.run() } catch { return false }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        ps.waitUntilExit()
        var ok = false
        for line in String(data: data, encoding: .utf8)?.split(separator: "\n") ?? [] {
            let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2,
                  parts[1].trimmingCharacters(in: .whitespaces) == "ghostty",
                  let pid = pid_t(parts[0].trimmingCharacters(in: .whitespaces))
            else { continue }
            if kill(pid, SIGUSR2) == 0 { ok = true }
        }
        return ok
    }

    // MARK: - file watching

    /// Watch the shader's directory (atomic saves replace the inode, so
    /// watching the file itself would go stale after one save) and fold
    /// external edits — claude-token.py, git — back into the UI.
    private func startWatching() {
        watcher?.cancel()
        guard let dir = shaderURL?.deletingLastPathComponent() else { return }
        let fd = Darwin.open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write], queue: .main)
        source.setEventHandler { [weak self] in
            self?.scheduleRescan()
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    private func scheduleRescan() {
        rescanTimer?.invalidate()
        rescanTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
            self?.mergeExternal()
        }
    }

    private func mergeExternal() {
        guard let fresh = try? parseFile() else { return }
        if fresh.map(\.name) != params.map(\.name) {
            params = fresh
            return
        }
        for fp in fresh {
            // a param the user touched in the last moment wins over the disk
            if let t = lastTouched[fp.name], Date().timeIntervalSince(t) < 0.6 { continue }
            if pending[fp.name] != nil { continue }
            if let i = params.firstIndex(where: { $0.name == fp.name }), params[i].value != fp.value {
                params[i].value = fp.value
            }
        }
    }
}
