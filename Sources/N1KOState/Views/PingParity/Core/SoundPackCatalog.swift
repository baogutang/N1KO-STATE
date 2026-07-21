// N1KO modification notice: adapted from Ping Island commit da130d6 for
// N1KO identity, manifest-size limits, and symlink-safe local-pack confinement.

import AppKit
import Combine
import Foundation

struct OpenPeonSoundEntry: Decodable, Equatable {
    let file: String
    let label: String?
    let sha256: String?
}

struct OpenPeonCategoryManifest: Decodable, Equatable {
    let sounds: [OpenPeonSoundEntry]
}

struct OpenPeonManifest: Decodable, Equatable {
    let cespVersion: String
    let name: String
    let displayName: String?
    let version: String?
    let description: String?
    let categories: [String: OpenPeonCategoryManifest]

    enum CodingKeys: String, CodingKey {
        case cespVersion = "cesp_version"
        case name
        case displayName = "display_name"
        case version
        case description
        case categories
    }
}

struct SoundPack: Identifiable, Equatable {
    let rootURL: URL
    let manifest: OpenPeonManifest

    var id: String { rootURL.path }

    var displayName: String {
        manifest.displayName ?? manifest.name
    }

    var detailText: String {
        if let version = manifest.version, !version.isEmpty {
            return version
        }
        return rootURL.lastPathComponent
    }

    func sounds(for category: String) -> [OpenPeonSoundEntry] {
        manifest.categories[category]?.sounds ?? []
    }
}

@MainActor
final class SoundPackCatalog: NSObject, ObservableObject, NSSoundDelegate {
    static let shared = SoundPackCatalog()
    static let maximumManifestBytes = 256 * 1_024

    @Published private(set) var availablePacks: [SoundPack] = []

    private let defaults = UserDefaults.standard
    private var lastPlayedSoundPathByCategory: [String: String] = [:]

    private enum Keys {
        static let importedPackPaths = "agent.sound.importedPackPaths"
    }

    private override init() {
        super.init()
        refresh()
    }

    func refresh() {
        var dedupedRoots: [String: URL] = [:]
        for url in discoverPackRoots() + importedPackRoots() {
            let standardized = url.standardizedFileURL.resolvingSymlinksInPath()
            dedupedRoots[standardized.path] = standardized
        }

        let packs = dedupedRoots.values.compactMap(loadPack(at:))
            .sorted {
                if $0.displayName == $1.displayName {
                    return $0.rootURL.path < $1.rootURL.path
                }
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }

        availablePacks = packs
    }

    func importPack() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = AppLocalization.string("导入")
        panel.message = AppLocalization.string("选择包含 openpeon.json 的音效包目录。")

        guard panel.runModal() == .OK,
              let url = panel.url?.standardizedFileURL.resolvingSymlinksInPath() else {
            return false
        }
        guard loadPack(at: url) != nil else {
            NSSound.beep()
            return false
        }

        var paths = Set(importedPackRoots().map(\.path))
        paths.insert(url.path)
        defaults.set(Array(paths).sorted(), forKey: Keys.importedPackPaths)
        refresh()
        return true
    }

    func pack(for path: String?) -> SoundPack? {
        guard let path, !path.isEmpty else { return nil }
        let resolvedPath = URL(fileURLWithPath: path, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
        return availablePacks.first { $0.rootURL.path == resolvedPath }
    }

    func displayName(for path: String?) -> String {
        pack(for: path)?.displayName ?? AppLocalization.string("未选择")
    }

    @discardableResult
    func play(event: NotificationEvent, packPath: String?, volume: Float) -> Bool {
        guard let pack = pack(for: packPath) else { return false }

        for category in event.cespCategories {
            if play(category: category, in: pack, volume: volume) {
                return true
            }
        }

        return false
    }

    private func play(category: String, in pack: SoundPack, volume: Float) -> Bool {
        let entries = pack.sounds(for: category)
        guard !entries.isEmpty else { return false }

        let playable = entries.compactMap { entry -> (OpenPeonSoundEntry, URL)? in
            guard let url = resolvedSoundURL(for: entry, in: pack) else { return nil }
            return (entry, url)
        }
        guard !playable.isEmpty else { return false }

        let lastPlayedPath = lastPlayedSoundPathByCategory[category]
        let selectable = playable.filter { $0.0.file != lastPlayedPath }
        guard let selected = (selectable.isEmpty ? playable : selectable).randomElement(),
              let sound = NSSound(contentsOf: selected.1, byReference: true) else {
            return false
        }

        sound.delegate = self
        let didPlay = AppSoundPlayback.shared.play(sound, volume: volume)
        if !didPlay {
            sound.delegate = nil
            return false
        }

        lastPlayedSoundPathByCategory[category] = selected.0.file
        return true
    }

    func sound(_ sound: NSSound, didFinishPlaying flag: Bool) {
        AppSoundPlayback.shared.clearIfActive(sound)
    }

    private func importedPackRoots() -> [URL] {
        let paths = defaults.stringArray(forKey: Keys.importedPackPaths) ?? []
        return paths.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    private func discoverPackRoots() -> [URL] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)

        let candidateDirectories = [
            home.appendingPathComponent(".openpeon/packs", isDirectory: true),
            home.appendingPathComponent(".claude/hooks/peon-ping/packs", isDirectory: true),
            cwd.appendingPathComponent(".claude/hooks/peon-ping/packs", isDirectory: true)
        ]

        var roots: [URL] = []
        for directory in candidateDirectories where fileExists(directory) {
            roots.append(contentsOf: packDirectories(in: directory))
        }
        return roots
    }

    private func packDirectories(in directory: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var roots: [URL] = []
        for case let url as URL in enumerator {
            guard url.lastPathComponent == "openpeon.json" else { continue }
            roots.append(url.deletingLastPathComponent())
            enumerator.skipDescendants()
        }
        return roots
    }

    private func loadPack(at rootURL: URL) -> SoundPack? {
        let root = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        let manifestURL = root.appendingPathComponent("openpeon.json")
        guard let values = try? manifestURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              let size = values.fileSize,
              size > 0,
              size <= Self.maximumManifestBytes else {
            return nil
        }

        do {
            let data = try Data(contentsOf: manifestURL, options: [.mappedIfSafe])
            let manifest = try JSONDecoder().decode(OpenPeonManifest.self, from: data)
            guard manifest.cespVersion.hasPrefix("1."),
                  !manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return SoundPack(rootURL: root, manifest: manifest)
        } catch {
            return nil
        }
    }

    private func resolvedSoundURL(for entry: OpenPeonSoundEntry, in pack: SoundPack) -> URL? {
        let relative = entry.file.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !relative.isEmpty,
              relative.count <= 1_024,
              !relative.hasPrefix("/"),
              !relative.split(separator: "/").contains("..") else {
            return nil
        }

        let root = pack.rootURL.standardizedFileURL.resolvingSymlinksInPath()
        let resolved = root.appendingPathComponent(relative)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"

        guard resolved.path.hasPrefix(rootPath),
              fileExists(resolved),
              hasSupportedAudioExtension(resolved),
              hasValidMagicBytes(resolved) else {
            return nil
        }

        return resolved
    }

    private func hasSupportedAudioExtension(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["mp3", "wav", "ogg"].contains(ext)
    }

    private func hasValidMagicBytes(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url),
              let data = try? handle.read(upToCount: 12) else {
            return false
        }
        try? handle.close()

        let bytes = [UInt8](data)
        switch url.pathExtension.lowercased() {
        case "wav":
            return bytes.starts(with: [0x52, 0x49, 0x46, 0x46])
        case "ogg":
            return bytes.starts(with: [0x4F, 0x67, 0x67, 0x53])
        case "mp3":
            if bytes.starts(with: [0x49, 0x44, 0x33]) { return true }
            return bytes.count >= 2 && bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0
        default:
            return false
        }
    }

    private func fileExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}
