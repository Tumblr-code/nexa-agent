import Foundation

/// Finds the Claude Code engine binary. GUI apps get a minimal PATH, so well-known install locations are checked
/// directly; the desktop app's Code tab installs the same engine under `~/.local/share/claude/versions`. `PATH` comes
/// last, as for every client's executable (`Executables`).
public enum ClaudeEngineLocator {
    public static func candidates(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                                  path: String = ProcessInfo.processInfo.environment["PATH"] ?? "") -> [URL] {
        var list = [
            home.appendingPathComponent(".local/bin/claude"),
            home.appendingPathComponent(".claude/local/claude"),
            URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
            URL(fileURLWithPath: "/usr/local/bin/claude"),
        ]
        let versions = home.appendingPathComponent(".local/share/claude/versions", isDirectory: true)
        if let names = try? FileManager.default.contentsOfDirectory(atPath: versions.path) {
            let sorted = names.filter { !$0.hasPrefix(".") }.sorted { lhs, rhs in
                lhs.compare(rhs, options: .numeric) == .orderedDescending
            }
            list += sorted.map { versions.appendingPathComponent($0) }
        }
        // The Claude desktop app keeps its own engine as an app bundle: claude-code/<version>/<build>/claude.app.
        let desktop = home.appendingPathComponent("Library/Application Support/Claude/claude-code", isDirectory: true)
        if let names = try? FileManager.default.contentsOfDirectory(atPath: desktop.path) {
            for version in names.filter({ !$0.hasPrefix(".") }).sorted(by: { $0.compare($1, options: .numeric) == .orderedDescending }) {
                let builds = (try? FileManager.default.contentsOfDirectory(atPath: desktop.appendingPathComponent(version).path)) ?? []
                list += builds.filter { !$0.hasPrefix(".") }.map {
                    desktop.appendingPathComponent(version).appendingPathComponent($0)
                        .appendingPathComponent("claude.app/Contents/MacOS/claude")
                }
            }
        }
        return list + Executables.onPath("claude", path: path)
    }

    public static func find(home: URL = FileManager.default.homeDirectoryForCurrentUser, fileManager: FileManager = .default,
                            path: String = ProcessInfo.processInfo.environment["PATH"] ?? "") -> URL? {
        Executables.first(candidates(home: home, path: path), fileManager: fileManager)
    }
}
