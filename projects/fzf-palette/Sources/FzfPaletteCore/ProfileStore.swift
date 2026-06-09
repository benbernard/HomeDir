import Foundation

public enum ProfileStoreError: Error, Equatable, CustomStringConvertible {
    case unknownProfile(String)
    case invalidProfile(name: String, issues: [ProfileValidationIssue])

    public var description: String {
        switch self {
        case .unknownProfile(let name):
            return "Unknown profile: \(name)"
        case .invalidProfile(let name, let issues):
            let details = issues.map { "\($0.field): \($0.message)" }.joined(separator: "; ")
            return "Invalid profile \(name): \(details)"
        }
    }
}

public struct ProfileCollection: Codable, Equatable {
    public var profiles: [PickerProfile]
    public var hotkeys: [ProfileHotKeyBinding]

    public init(profiles: [PickerProfile], hotkeys: [ProfileHotKeyBinding] = []) {
        self.profiles = profiles
        self.hotkeys = hotkeys
    }

    private enum CodingKeys: String, CodingKey {
        case profiles
        case hotkeys
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profiles = try container.decodeIfPresent([PickerProfile].self, forKey: .profiles) ?? []
        hotkeys = try container.decodeIfPresent([ProfileHotKeyBinding].self, forKey: .hotkeys) ?? []
    }
}

public struct ProfileStore: Equatable {
    public var profiles: [String: PickerProfile]
    public var hotkeys: [ProfileHotKeyBinding]

    public init(profiles: [PickerProfile] = Self.builtInProfiles, hotkeys: [ProfileHotKeyBinding] = []) {
        var profilesByName: [String: PickerProfile] = [:]
        for profile in profiles {
            profilesByName[profile.name] = profile
        }
        self.profiles = profilesByName
        self.hotkeys = hotkeys
    }

    public static let builtInProfiles: [PickerProfile] = [
        PickerProfile(
            name: "default",
            title: "Files",
            source: .profile
        ),
        PickerProfile(
            name: FzfSourceCommands.ctrlTProfileName,
            title: "Files",
            source: .profile,
            display: DisplayConfig(
                prompt: "files>",
                header: "Pick files",
                pointer: ">",
                marker: "*",
                info: "inline"
            )
        ),
        PickerProfile(
            name: "repos",
            title: "Repos",
            source: .command("find \"$HOME/projects\" \"$HOME/repos\" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort"),
            display: DisplayConfig(prompt: "repos>", header: "Pick a repo", info: "inline"),
            result: ResultConfig(mode: .return)
        ),
        PickerProfile(
            name: "downloads",
            title: "Downloads",
            source: .command("ls -1t \"$HOME/Downloads\" 2>/dev/null"),
            display: DisplayConfig(prompt: "downloads>", header: "Recent downloads", info: "inline"),
            result: ResultConfig(mode: .return)
        ),
        PickerProfile(
            name: "context-files",
            title: "Context Files",
            source: .twoStage(TwoStageSource(
                first: PickerStage(
                    title: "Choose Root",
                    source: .command(contextRootsCommand),
                    display: DisplayConfig(
                        delimiter: "\t",
                        withNth: "1",
                        prompt: "roots>",
                        header: "Pick a root",
                        info: "inline"
                    ),
                    result: ResultConfig(fields: "2")
                ),
                second: PickerStage(
                    title: "Files",
                    source: .command(contextFilesCommand),
                    fzfOptions: ["--preview-window=right:60%:wrap", "--bind", "ctrl-/:toggle-preview"],
                    display: DisplayConfig(
                        delimiter: "\t",
                        withNth: "1",
                        prompt: "files>",
                        header: "Pick a file or directory",
                        info: "inline"
                    ),
                    preview: PreviewConfig(
                        command: "if [ -d {2} ]; then ls -la {2}; else bat --color always {2} 2>/dev/null || sed -n '1,160p' {2}; fi",
                        window: "right:60%:wrap"
                    ),
                    result: ResultConfig(mode: .return, fields: "2")
                )
            ))
        ),
        PickerProfile(
            name: "git-status",
            title: "Git Status",
            source: .command("git status --short"),
            fzfOptions: ["--ansi", "--preview-window=right:60%:wrap"],
            display: DisplayConfig(ansi: true, prompt: "status>", header: "Git status", info: "inline"),
            preview: PreviewConfig(command: "git diff --color=always -- {}", window: "right:60%:wrap"),
            result: ResultConfig(mode: .return)
        ),
        PickerProfile(
            name: "git-commits",
            title: "Commits",
            source: .command("git log --pretty=oneline --abbrev-commit --color=always"),
            fzfOptions: ["--ansi", "--preview-window=right:60%:wrap"],
            display: DisplayConfig(ansi: true, delimiter: " ", prompt: "commits>", header: "Git commits", info: "inline"),
            preview: PreviewConfig(command: "git show --color=always {1}", window: "right:60%:wrap"),
            result: ResultConfig(mode: .return, fields: "1")
        )
    ]

    private static let contextRootsCommand = #"""
printf '~\t%s\n' "$HOME"
for container in "$HOME/projects" "$HOME/repos"; do
  [ -d "$container" ] && find "$container" -mindepth 1 -maxdepth 1 -type d -print
done | sort | awk -F/ '{printf "%s\t%s\n", $NF, $0}'
"""#

    private static let contextFilesCommand = #"""
root={}
find "$root" -mindepth 1 -maxdepth 6 \( -name .git -o -name node_modules \) -prune -o \( -type f -o -type d \) -print 2>/dev/null | awk -v root="$root" 'index($0, root "/") == 1 { rel=substr($0, length(root)+2); if (rel != "") print rel "\t" $0 }'
"""#

    public static func load(
        fileURL: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> ProfileStore {
        let url = fileURL ?? configuredProfilesURL(environment: environment)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return ProfileStore()
        }

        let data = try Data(contentsOf: url)
        let collection = try decodeCollection(from: data)
        return ProfileStore(profiles: builtInProfiles + collection.profiles, hotkeys: collection.hotkeys)
    }

    public func profile(named name: String) -> PickerProfile? {
        profiles[name]
    }

    public func resolvedRequest(for request: PickerRequest) throws -> PickerRequest {
        guard let profile = profile(named: request.profile) else {
            throw ProfileStoreError.unknownProfile(request.profile)
        }

        let issues = profile.validationErrors()
        guard issues.isEmpty else {
            throw ProfileStoreError.invalidProfile(name: profile.name, issues: issues)
        }

        return request.applying(profile: profile)
    }

    private static func configuredProfilesURL(environment: [String: String]) -> URL {
        if let path = environment["FZF_PALETTE_PROFILES_FILE"], !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        return FzfPalettePaths.profilesURL
    }

    private static func decodeCollection(from data: Data) throws -> ProfileCollection {
        let decoder = JSONDecoder()
        if let collection = try? decoder.decode(ProfileCollection.self, from: data) {
            return collection
        }
        return try ProfileCollection(profiles: decoder.decode([PickerProfile].self, from: data))
    }
}

public extension PickerStage {
    func resolvedRequest(base request: PickerRequest, selectedText: String? = nil) -> PickerRequest {
        let selectedText = selectedText ?? ""
        let resolvedTitle = title.map { Self.replaceRawPlaceholders(in: $0, selectedText: selectedText) }
        let resolvedCwd = cwd.map { Self.replaceRawPlaceholders(in: $0, selectedText: selectedText) }
        return PickerRequest(
            id: request.id,
            profile: resolvedTitle ?? request.profile,
            cwd: resolvedCwd ?? request.cwd,
            query: query.isEmpty && selectedText.isEmpty ? request.query : query,
            source: source.pickerSource(selectedText: selectedText),
            fzfOptions: request.fzfOptions + fzfOptions,
            display: display,
            preview: preview,
            env: request.env,
            input: nil,
            result: result,
            resultMode: request.resultMode == .return ? result.mode : request.resultMode,
            timeoutMs: request.timeoutMs
        )
    }

    private static func replaceRawPlaceholders(in template: String, selectedText: String) -> String {
        template.replacingOccurrences(of: "{}", with: selectedText)
    }
}

private extension StageSource {
    func pickerSource(selectedText: String) -> PickerSource {
        switch self {
        case let .command(command):
            return .command(PlaceholderExpansion.expand(template: command, row: selectedText))
        case let .staticItems(items):
            return .staticItems(items.map { $0.replacingOccurrences(of: "{}", with: selectedText) })
        }
    }
}

public extension PickerRequest {
    func applying(profile: PickerProfile) -> PickerRequest {
        let mergedDisplay = display.applying(profile: profile.display)
        let mergedPreview = preview.applying(profile: profile.preview)
        let mergedResult = result.applying(profile: profile.result)

        return PickerRequest(
            id: id,
            profile: profile.name,
            cwd: profile.cwd ?? cwd,
            query: query.isEmpty ? profile.query : query,
            source: source == .profile ? profile.source : source,
            fzfOptions: profile.fzfOptions + fzfOptions,
            display: mergedDisplay,
            preview: mergedPreview,
            env: env,
            input: input,
            result: mergedResult,
            resultMode: resultMode == .return ? mergedResult.mode : resultMode,
            timeoutMs: timeoutMs
        )
    }
}

private extension DisplayConfig {
    func applying(profile: DisplayConfig) -> DisplayConfig {
        DisplayConfig(
            ansi: profile.ansi || ansi,
            delimiter: delimiter ?? profile.delimiter,
            nth: nth ?? profile.nth,
            withNth: withNth ?? profile.withNth,
            prompt: prompt ?? profile.prompt,
            header: header ?? profile.header,
            pointer: pointer ?? profile.pointer,
            marker: marker ?? profile.marker,
            info: info ?? profile.info
        )
    }
}

private extension Optional where Wrapped == PreviewConfig {
    func applying(profile: PreviewConfig?) -> PreviewConfig? {
        guard let requestPreview = self else {
            return profile
        }
        guard requestPreview.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let profile else {
            return requestPreview
        }
        return PreviewConfig(
            command: profile.command,
            window: requestPreview.window,
            debounceMs: requestPreview.debounceMs
        )
    }
}

private extension ResultConfig {
    func applying(profile: ResultConfig) -> ResultConfig {
        let defaultResult = ResultConfig()
        return ResultConfig(
            mode: mode == defaultResult.mode ? profile.mode : mode,
            fields: fields ?? profile.fields,
            join: join == defaultResult.join ? profile.join : join,
            command: command ?? profile.command
        )
    }
}
