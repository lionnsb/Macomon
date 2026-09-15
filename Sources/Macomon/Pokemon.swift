import Foundation

struct Pokemon: Hashable {
    let generation: Int
    let identifier: String
    let directoryURL: URL
    let files: Set<String>

    var id: String {
        generation == 0 ? "pets/\(identifier)" : "gen\(generation)/\(identifier)"
    }

    var isCompanion: Bool { generation == 0 }

    var displayName: String {
        Self.format(identifier)
    }

    var hasShiny: Bool {
        files.contains { $0.hasPrefix("shiny_") }
    }

    var availableBehaviors: [String] {
        let behaviors = files.compactMap { filename -> String? in
            guard filename.hasSuffix(".gif") else { return nil }

            let stem = String(filename.dropLast(4))
            guard let firstSeparator = stem.firstIndex(of: "_") else { return nil }
            var behavior = String(stem[stem.index(after: firstSeparator)...])
            behavior = behavior.replacingOccurrences(
                of: #"_\d+fps$"#,
                with: "",
                options: .regularExpression
            )
            if behavior.hasSuffix("_left") {
                behavior.removeLast("_left".count)
            }
            return behavior
        }

        let unique = Set(behaviors)
        let preferredOrder = [
            "idle", "walk", "sleep_zzz", "happy_hearts", "rain_umbrella", "tail_wag",
            "stretch_yawn", "jump", "roll_over", "sniff_discover", "fetch_ball",
            "treat_catch", "high_five", "chase_tail", "zoomies", "digging", "bark_alert",
            "sit_tail_sway", "banana_eat", "climb_vine", "swing_vine", "dance",
            "wave", "clap", "scratch_head", "coconut_play", "sneeze", "rain_leaf",
            "frontflip"
        ]
        return unique.sorted { lhs, rhs in
            let leftIndex = preferredOrder.firstIndex(of: lhs) ?? Int.max
            let rightIndex = preferredOrder.firstIndex(of: rhs) ?? Int.max
            return leftIndex == rightIndex ? lhs < rhs : leftIndex < rightIndex
        }
    }

    func animationURL(variant: String, behavior: String, facingLeft: Bool) -> URL? {
        let directionalBehavior = facingLeft ? "\(behavior)_left" : behavior

        if let exact = matchingFile(variant: variant, behavior: directionalBehavior) {
            return directoryURL.appendingPathComponent(exact)
        }

        if let regular = matchingFile(variant: variant, behavior: behavior) {
            return directoryURL.appendingPathComponent(regular)
        }

        if variant == "shiny", let fallback = matchingFile(variant: "default", behavior: directionalBehavior)
            ?? matchingFile(variant: "default", behavior: behavior) {
            return directoryURL.appendingPathComponent(fallback)
        }

        return nil
    }

    func hasDedicatedLeftAnimation(variant: String, behavior: String) -> Bool {
        matchingFile(variant: variant, behavior: "\(behavior)_left") != nil
    }

    func behavior(matching candidates: [String]) -> String? {
        let behaviors = availableBehaviors
        for candidate in candidates {
            let normalizedCandidate = candidate.lowercased()
            if let behavior = behaviors.first(where: { available in
                let normalizedBehavior = available.lowercased()
                return normalizedBehavior == normalizedCandidate
                    || normalizedBehavior.hasPrefix(normalizedCandidate + "_")
                    || normalizedCandidate.hasPrefix(normalizedBehavior + "_")
            }) {
                return behavior
            }
        }
        return nil
    }

    private func matchingFile(variant: String, behavior: String) -> String? {
        files.first { filename in
            filename.range(
                of: #"^\#(variant)_\#(behavior)(?:_\d+fps)?\.gif$"#,
                options: .regularExpression
            ) != nil
        }
    }

    private static func format(_ identifier: String) -> String {
        identifier
            .split(separator: "_")
            .map { word in
                let raw = String(word)
                switch raw {
                case "hooh": return "Ho-Oh"
                case "porygonz": return "Porygon-Z"
                case "mrmime": return "Mr. Mime"
                default: return raw.prefix(1).uppercased() + raw.dropFirst()
                }
            }
            .joined(separator: " ")
    }
}

struct PokemonLibrary {
    let pokemon: [Pokemon]

    init(resourceRoot: URL) {
        let fileManager = FileManager.default
        var discovered: [Pokemon] = []

        let collections = [(generation: 0, directory: "pets")]
            + (1...5).map { (generation: $0, directory: "gen\($0)") }

        for collection in collections {
            let generationURL = resourceRoot.appendingPathComponent(collection.directory, isDirectory: true)
            guard let directories = try? fileManager.contentsOfDirectory(
                at: generationURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for directory in directories {
                let isDirectory = (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                guard isDirectory else { continue }

                let gifFiles = (try? fileManager.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                ))?
                    .filter { $0.pathExtension.lowercased() == "gif" }
                    .map(\.lastPathComponent) ?? []

                guard !gifFiles.isEmpty else { continue }
                discovered.append(Pokemon(
                    generation: collection.generation,
                    identifier: directory.lastPathComponent,
                    directoryURL: directory,
                    files: Set(gifFiles)
                ))
            }
        }

        pokemon = discovered.sorted {
            $0.generation == $1.generation
                ? $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                : $0.generation < $1.generation
        }
    }

    func pokemon(withID id: String?) -> Pokemon? {
        pokemon.first { $0.id == id }
    }
}
