import Foundation

enum SelfTest {
    static func run() -> Bool {
        let resourceRoot = ResourceLocator.root().standardizedFileURL
        if Bundle.main.bundleURL.pathExtension == "app",
           !resourceRoot.path.hasPrefix(Bundle.main.bundleURL.standardizedFileURL.path + "/") {
            writeError("Das App-Bundle verwendet Ressourcen außerhalb des eigenen Pakets: \(resourceRoot.path)")
            return false
        }
        if Bundle.main.bundleURL.pathExtension == "app" {
            guard let resources = Bundle.main.resourceURL,
                  ResourceLocator.dogMarkURL() != nil,
                  FileManager.default.fileExists(
                    atPath: resources.appendingPathComponent("Macomon.icns").path
                  ) else {
                writeError("Das Begleiter-Logo oder App-Icon fehlt im App-Bundle.")
                return false
            }
        }

        let library = PokemonLibrary(resourceRoot: resourceRoot)
        guard library.pokemon.count == 636 else {
            writeError("Erwartet: 636 Figuren, gefunden: \(library.pokemon.count)")
            return false
        }

        var gifCount = 0
        var invalidFiles: [String] = []

        for pokemon in library.pokemon {
            for filename in pokemon.files.sorted() {
                gifCount += 1
                let url = pokemon.directoryURL.appendingPathComponent(filename)
                if GIFAnimation.load(from: url) == nil {
                    invalidFiles.append("\(pokemon.id)/\(filename)")
                }
            }
        }

        guard gifCount == 2_482 else {
            writeError("Erwartet: 2482 GIFs, gefunden: \(gifCount)")
            return false
        }

        guard invalidFiles.isEmpty else {
            writeError("Nicht lesbare GIFs: \(invalidFiles.joined(separator: ", "))")
            return false
        }

        let expectedDogBehaviors: Set<String> = [
            "idle", "walk", "sleep_zzz", "happy_hearts", "fetch_ball", "jump",
            "roll_over", "sniff_discover", "tail_wag", "treat_catch", "bark_alert",
            "chase_tail", "digging", "high_five", "stretch_yawn", "zoomies",
            "rain_umbrella"
        ]
        guard let dog = library.pokemon(withID: "pets/kleiner_hund"),
              Set(dog.availableBehaviors) == expectedDogBehaviors else {
            writeError("Der kleine Hund oder eine seiner Animationen fehlt.")
            return false
        }

        guard dog.behavior(matching: ["night", "sleep"]) == "sleep_zzz" else {
            writeError("Die Uhrzeitreaktion des kleinen Hundes wurde nicht erkannt.")
            return false
        }
        guard dog.behavior(matching: ["rain", "rainy", "umbrella"]) == "rain_umbrella" else {
            writeError("Die Regenreaktion des kleinen Hundes wurde nicht erkannt.")
            return false
        }

        let allDogBehaviors = dog.availableBehaviors
        let regularDogBehaviors = expectedDogBehaviors.subtracting(["rain_umbrella"])
        guard Set(PokemonAnimator.CompanionMode.randomAll.candidateBehaviors(from: allDogBehaviors))
                == regularDogBehaviors else {
            writeError("Der zufällige Begleiter-Modus enthält unerwartete Kontextverhalten.")
            return false
        }
        guard Set(PokemonAnimator.CompanionMode.calm.candidateBehaviors(from: allDogBehaviors))
                == Set(["idle", "sleep_zzz", "tail_wag", "sniff_discover", "stretch_yawn", "walk"]) else {
            writeError("Der ruhige Begleiter-Modus enthält unerwartete Verhalten.")
            return false
        }
        guard !PokemonAnimator.CompanionMode.playful.candidateBehaviors(from: allDogBehaviors)
                .contains("sleep_zzz") else {
            writeError("Der verspielte Begleiter-Modus enthält eine Schlafanimation.")
            return false
        }
        guard PokemonAnimator.interactionBehaviors(from: allDogBehaviors).contains("high_five"),
              PokemonAnimator.interactionBehaviors(from: allDogBehaviors).contains("happy_hearts") else {
            writeError("Die Mausinteraktion findet keine passende Hundereaktion.")
            return false
        }

        let expectedMonkeyBehaviors: Set<String> = [
            "idle", "walk", "sleep_zzz", "happy_hearts", "sit_tail_sway",
            "banana_eat", "jump", "climb_vine", "swing_vine", "roll_over",
            "dance", "wave", "clap", "scratch_head", "coconut_play", "sneeze",
            "rain_leaf", "frontflip"
        ]
        guard let monkey = library.pokemon(withID: "pets/baby_affe"),
              Set(monkey.availableBehaviors) == expectedMonkeyBehaviors,
              monkey.hasDedicatedLeftAnimation(variant: "default", behavior: "walk") else {
            writeError("Der Baby-Affe oder eine seiner Animationen fehlt.")
            return false
        }
        guard monkey.behavior(matching: ["rain", "rainy", "umbrella"]) == "rain_leaf" else {
            writeError("Die Regenreaktion des Baby-Affen wurde nicht erkannt.")
            return false
        }
        guard Set(PokemonAnimator.CompanionMode.randomAll.candidateBehaviors(
            from: monkey.availableBehaviors
        )) == expectedMonkeyBehaviors.subtracting(["rain_leaf"]) else {
            writeError("Der Baby-Affe verwendet seine Regenanimation außerhalb des Wetters.")
            return false
        }
        guard PokemonAnimator.CompanionMode.playful.candidateBehaviors(
            from: monkey.availableBehaviors
        ).contains("coconut_play"),
        PokemonAnimator.CompanionMode.active.candidateBehaviors(
            from: monkey.availableBehaviors
        ).contains("frontflip"),
        PokemonAnimator.interactionBehaviors(from: monkey.availableBehaviors).contains("wave") else {
            writeError("Die Begleiter-Profile des Baby-Affen sind unvollständig.")
            return false
        }

        if let pikachu = library.pokemon(withID: "gen1/pikachu"),
           pikachu.behavior(matching: ["rain", "snow", "night"]) != nil {
            writeError("Eine Figur ohne passende Animation erhielt eine Umgebungsreaktion.")
            return false
        }

        guard PetMovementSpeed.relaxed.multiplier < PetMovementSpeed.normal.multiplier,
              PetMovementSpeed.normal.multiplier < PetMovementSpeed.fast.multiplier,
              PetTravelRange.short.overlayDistance < PetTravelRange.medium.overlayDistance,
              PetTravelRange.medium.overlayDistance < PetTravelRange.long.overlayDistance else {
            writeError("Die Bewegungsprofile sind nicht korrekt abgestuft.")
            return false
        }

        guard PowerReactionController.candidates(
            isCharging: true,
            usesBattery: false,
            capacity: 80
        ).contains("happy"),
        PowerReactionController.candidates(
            isCharging: false,
            usesBattery: true,
            capacity: 10
        ).contains("sleep"),
        PowerReactionController.candidates(
            isCharging: false,
            usesBattery: true,
            capacity: 70
        ).isEmpty else {
            writeError("Die Akku- und Ladereaktionen sind fehlerhaft.")
            return false
        }

        print("Macomon-V1.4-Selbsttest erfolgreich: Figuren, Begleiter, Animationen, Interaktion, Bewegung und Systemreaktionen geprüft.")
        return true
    }

    private static func writeError(_ message: String) {
        let data = Data("Macomon-Selbsttest fehlgeschlagen: \(message)\n".utf8)
        FileHandle.standardError.write(data)
    }
}
