import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var library: PokemonLibrary!
    private var selectedPokemon: Pokemon!
    private var animator: PokemonAnimator!
    private var overlayController: PetOverlayController!
    private var reactionController: EnvironmentReactionController!
    private var powerReactionController: PowerReactionController!
    private var menu: NSMenu!
    private var pokemonMenuItems: [NSMenuItem] = []
    private var shinyItem: NSMenuItem!
    private var pauseItem: NSMenuItem!
    private var environmentReactionItem: NSMenuItem!
    private var powerReactionItem: NSMenuItem!
    private var launchAtLoginItem: NSMenuItem!
    private var modeItems: [PokemonAnimator.PlaybackMode: NSMenuItem] = [:]
    private var companionModeItem: NSMenuItem!
    private var companionModeItems: [PokemonAnimator.CompanionMode: NSMenuItem] = [:]
    private var locationItems: [PetLocation: NSMenuItem] = [:]
    private var sizeItems: [PetSizePreset: NSMenuItem] = [:]
    private var speedItems: [PetMovementSpeed: NSMenuItem] = [:]
    private var rangeItems: [PetTravelRange: NSMenuItem] = [:]
    private var selectedLocation: PetLocation = .menuBar
    private var selectedSize: PetSizePreset = .large
    private var selectedMovementSpeed: PetMovementSpeed = .normal
    private var selectedTravelRange: PetTravelRange = .medium
    private lazy var launchAtLogin = LaunchAtLoginManager()
    private var isPaused = false
    private var environmentReactionsEnabled = true
    private var powerReactionsEnabled = true
    private var environmentCandidates: [String] = []
    private var powerCandidates: [String] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        library = PokemonLibrary(resourceRoot: ResourceLocator.root())
        guard !library.pokemon.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "Keine Pokémon gefunden"
            alert.informativeText = "Die Animationsordner gen1 bis gen5 fehlen im App-Bundle."
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        let savedID = UserDefaults.standard.string(forKey: "selectedPokemon")
        selectedPokemon = library.pokemon(withID: savedID)
            ?? library.pokemon.first { $0.identifier == "pikachu" }
            ?? library.pokemon[0]
        if let rawLocation = UserDefaults.standard.string(forKey: "petLocation"),
           let location = PetLocation(rawValue: rawLocation) {
            selectedLocation = location
        }
        if let rawSize = UserDefaults.standard.string(forKey: "petSize"),
           let size = PetSizePreset(rawValue: rawSize) {
            selectedSize = size
        }
        if let rawSpeed = UserDefaults.standard.string(forKey: "movementSpeed"),
           let speed = PetMovementSpeed(rawValue: rawSpeed) {
            selectedMovementSpeed = speed
        }
        if let rawRange = UserDefaults.standard.string(forKey: "travelRange"),
           let range = PetTravelRange(rawValue: rawRange) {
            selectedTravelRange = range
        }
        if UserDefaults.standard.object(forKey: "environmentReactionsEnabled") != nil {
            environmentReactionsEnabled = UserDefaults.standard.bool(forKey: "environmentReactionsEnabled")
        } else {
            UserDefaults.standard.set(true, forKey: "environmentReactionsEnabled")
        }
        if UserDefaults.standard.object(forKey: "powerReactionsEnabled") != nil {
            powerReactionsEnabled = UserDefaults.standard.bool(forKey: "powerReactionsEnabled")
        } else {
            UserDefaults.standard.set(true, forKey: "powerReactionsEnabled")
        }

        statusItem = NSStatusBar.system.statusItem(withLength: 74)
        guard let button = statusItem.button else {
            NSApp.terminate(nil)
            return
        }

        overlayController = PetOverlayController()
        animator = PokemonAnimator(
            button: button,
            pokemon: selectedPokemon,
            displayDimension: selectedSize.dimension
        )
        animator.setMovementSettings(speed: selectedMovementSpeed, range: selectedTravelRange)
        overlayController.setMovementSettings(speed: selectedMovementSpeed, range: selectedTravelRange)
        overlayController.onDirectionChange = { [weak self] direction in
            self?.animator.setDirection(direction)
        }
        overlayController.onClick = { [weak self] in
            guard let self else { return }
            self.overlayController.present(self.menu)
        }
        overlayController.onInteraction = { [weak self] in
            self?.animator.triggerInteraction()
        }
        overlayController.onDragEnded = { [weak self] _ in
            guard let self else { return }
            self.selectedLocation = .free
            UserDefaults.standard.set(PetLocation.free.rawValue, forKey: "petLocation")
            self.updateMenuState()
        }
        animator.onFrame = { [weak self] image, behavior, direction in
            self?.overlayController.update(image: image, behavior: behavior, direction: direction)
        }
        reactionController = EnvironmentReactionController()
        reactionController.onCandidatesChange = { [weak self] candidates in
            self?.environmentCandidates = candidates
            self?.applyContextCandidates()
        }
        powerReactionController = PowerReactionController()
        powerReactionController.onCandidatesChange = { [weak self] candidates in
            self?.powerCandidates = candidates
            self?.applyContextCandidates()
        }
        menu = buildMenu()
        menu.delegate = self
        statusItem.menu = menu
        _ = launchAtLogin
        applyLocation()
        animator.refresh()
        if environmentReactionsEnabled {
            reactionController.start()
        }
        if powerReactionsEnabled {
            powerReactionController.start()
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateMenuState()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu(title: "Macomon")

        let currentItem = NSMenuItem(title: selectedPokemon.displayName, action: nil, keyEquivalent: "")
        currentItem.isEnabled = false
        currentItem.tag = 9_001
        menu.addItem(currentItem)

        let companions = library.pokemon.filter(\.isCompanion)
        if !companions.isEmpty {
            let companionItem = NSMenuItem(title: "Begleiter", action: nil, keyEquivalent: "")
            let companionMenu = NSMenu(title: "Begleiter")
            companionItem.submenu = companionMenu

            for companion in companions {
                let item = NSMenuItem(title: companion.displayName, action: #selector(selectPokemon(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = companion.id
                companionMenu.addItem(item)
                pokemonMenuItems.append(item)
            }

            menu.addItem(companionItem)
        }

        let generationsItem = NSMenuItem(title: "Pokémons", action: nil, keyEquivalent: "")
        let generationsMenu = NSMenu(title: "Pokémons")
        generationsItem.submenu = generationsMenu

        for generation in 1...5 {
            let generationItem = NSMenuItem(title: "Generation \(generation)", action: nil, keyEquivalent: "")
            let generationMenu = NSMenu(title: "Generation \(generation)")
            generationItem.submenu = generationMenu

            for pokemon in library.pokemon where pokemon.generation == generation {
                let item = NSMenuItem(title: pokemon.displayName, action: #selector(selectPokemon(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = pokemon.id
                generationMenu.addItem(item)
                pokemonMenuItems.append(item)
            }

            generationsMenu.addItem(generationItem)
        }
        menu.addItem(generationsItem)

        let randomItem = NSMenuItem(title: "Zufällige Figur", action: #selector(selectRandomPokemon), keyEquivalent: "r")
        randomItem.target = self
        menu.addItem(randomItem)
        menu.addItem(.separator())

        let displayItem = NSMenuItem(title: "Darstellung", action: nil, keyEquivalent: "")
        let displayMenu = NSMenu(title: "Darstellung")
        displayItem.submenu = displayMenu

        shinyItem = NSMenuItem(title: "Shiny", action: #selector(toggleShiny), keyEquivalent: "s")
        shinyItem.target = self

        let locationItem = NSMenuItem(title: "Aufenthaltsort", action: nil, keyEquivalent: "")
        let locationMenu = NSMenu(title: "Aufenthaltsort")
        locationItem.submenu = locationMenu
        let locations: [(PetLocation, String)] = [
            (.menuBar, "Menüleiste"),
            (.notch, "Notch"),
            (.desktop, "Desktop"),
            (.activeWindow, "Aktives Fenster / Tab Bar"),
            (.free, "Frei platziert")
        ]
        for (location, title) in locations {
            let item = NSMenuItem(title: title, action: #selector(selectLocation(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = location.rawValue
            locationMenu.addItem(item)
            locationItems[location] = item
        }
        displayMenu.addItem(locationItem)

        let sizeItem = NSMenuItem(title: "Größe", action: nil, keyEquivalent: "")
        let sizeMenu = NSMenu(title: "Größe")
        sizeItem.submenu = sizeMenu
        let sizes: [(PetSizePreset, String)] = [
            (.small, "Klein"),
            (.medium, "Mittel"),
            (.large, "Groß"),
            (.extraLarge, "Sehr groß")
        ]
        for (size, title) in sizes {
            let item = NSMenuItem(title: title, action: #selector(selectSize(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = size.rawValue
            sizeMenu.addItem(item)
            sizeItems[size] = item
        }
        displayMenu.addItem(sizeItem)
        displayMenu.addItem(.separator())
        displayMenu.addItem(shinyItem)
        menu.addItem(displayItem)

        let movementItem = NSMenuItem(title: "Bewegung", action: nil, keyEquivalent: "")
        let movementMenu = NSMenu(title: "Bewegung")
        movementItem.submenu = movementMenu

        let speedItem = NSMenuItem(title: "Geschwindigkeit", action: nil, keyEquivalent: "")
        let speedMenu = NSMenu(title: "Geschwindigkeit")
        speedItem.submenu = speedMenu
        let speeds: [(PetMovementSpeed, String)] = [
            (.relaxed, "Gemütlich"),
            (.normal, "Normal"),
            (.fast, "Schnell")
        ]
        for (speed, title) in speeds {
            let item = NSMenuItem(title: title, action: #selector(selectMovementSpeed(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = speed.rawValue
            speedMenu.addItem(item)
            speedItems[speed] = item
        }
        movementMenu.addItem(speedItem)

        let rangeItem = NSMenuItem(title: "Laufstrecke", action: nil, keyEquivalent: "")
        let rangeMenu = NSMenu(title: "Laufstrecke")
        rangeItem.submenu = rangeMenu
        let ranges: [(PetTravelRange, String)] = [
            (.short, "Kurz"),
            (.medium, "Mittel"),
            (.long, "Weit")
        ]
        for (range, title) in ranges {
            let item = NSMenuItem(title: title, action: #selector(selectTravelRange(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = range.rawValue
            rangeMenu.addItem(item)
            rangeItems[range] = item
        }
        movementMenu.addItem(rangeItem)
        menu.addItem(movementItem)

        let behaviorItem = NSMenuItem(title: "Verhalten", action: nil, keyEquivalent: "")
        let behaviorMenu = NSMenu(title: "Verhalten")
        behaviorItem.submenu = behaviorMenu

        let animationItem = NSMenuItem(title: "Animation", action: nil, keyEquivalent: "")
        let animationMenu = NSMenu(title: "Animation")
        animationItem.submenu = animationMenu
        let modes: [(PokemonAnimator.PlaybackMode, String)] = [
            (.automatic, "Automatisch"),
            (.walk, "Laufen"),
            (.idle, "Ausruhen"),
            (.sleep, "Schlafen"),
            (.happy, "Freuen"),
            (.rainUmbrella, "Regenreaktion"),
            (.tailWag, "Schwanz wedeln"),
            (.jump, "Springen"),
            (.rollOver, "Rolle machen"),
            (.sniffDiscover, "Schnüffeln"),
            (.fetchBall, "Ball holen"),
            (.treatCatch, "Leckerli fangen"),
            (.barkAlert, "Bellen / Aufpassen"),
            (.chaseTail, "Schwanz jagen"),
            (.digging, "Graben"),
            (.highFive, "High Five"),
            (.stretchYawn, "Strecken & Gähnen"),
            (.zoomies, "Herumflitzen"),
            (.sitTailSway, "Sitzen & Schwanz bewegen"),
            (.bananaEat, "Banane essen"),
            (.climbVine, "An Liane klettern"),
            (.swingVine, "An Liane schwingen"),
            (.dance, "Tanzen"),
            (.wave, "Winken"),
            (.clap, "Klatschen"),
            (.scratchHead, "Am Kopf kratzen"),
            (.coconutPlay, "Mit Kokosnuss spielen"),
            (.sneeze, "Niesen"),
            (.frontflip, "Vorwärtssalto")
        ]
        for (mode, title) in modes {
            let item = NSMenuItem(title: title, action: #selector(selectPlaybackMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            animationMenu.addItem(item)
            modeItems[mode] = item
        }
        behaviorMenu.addItem(animationItem)

        companionModeItem = NSMenuItem(title: "Begleiter-Modus", action: nil, keyEquivalent: "")
        let companionModeMenu = NSMenu(title: "Begleiter-Modus")
        companionModeItem.submenu = companionModeMenu
        let companionModes: [(PokemonAnimator.CompanionMode, String)] = [
            (.balanced, "Ausgeglichen"),
            (.randomAll, "Alle Animationen zufällig"),
            (.calm, "Ruhig"),
            (.playful, "Verspielt"),
            (.active, "Aktiv")
        ]
        for (mode, title) in companionModes {
            let item = NSMenuItem(title: title, action: #selector(selectCompanionMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            companionModeMenu.addItem(item)
            companionModeItems[mode] = item
        }
        companionModeMenu.addItem(.separator())
        let companionModeHint = NSMenuItem(
            title: "Steuert die automatische Animation",
            action: nil,
            keyEquivalent: ""
        )
        companionModeHint.isEnabled = false
        companionModeMenu.addItem(companionModeHint)
        behaviorMenu.addItem(companionModeItem)
        behaviorMenu.addItem(.separator())

        environmentReactionItem = NSMenuItem(
            title: "Auf Wetter & Uhrzeit reagieren",
            action: #selector(toggleEnvironmentReactions),
            keyEquivalent: ""
        )
        environmentReactionItem.target = self
        behaviorMenu.addItem(environmentReactionItem)

        powerReactionItem = NSMenuItem(
            title: "Auf Akku & Laden reagieren",
            action: #selector(togglePowerReactions),
            keyEquivalent: ""
        )
        powerReactionItem.target = self
        behaviorMenu.addItem(powerReactionItem)
        menu.addItem(behaviorItem)

        pauseItem = NSMenuItem(title: "Pausieren", action: #selector(togglePause), keyEquivalent: "p")
        pauseItem.target = self
        menu.addItem(pauseItem)

        menu.addItem(.separator())
        launchAtLoginItem = NSMenuItem(
            title: "Bei Anmeldung starten",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Macomon beenden", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        updateMenuState(in: menu)
        return menu
    }

    private func updateMenuState(in targetMenu: NSMenu? = nil) {
        let targetMenu = targetMenu ?? menu
        targetMenu?.item(withTag: 9_001)?.title = selectedPokemon.displayName

        for item in pokemonMenuItems {
            item.state = (item.representedObject as? String) == selectedPokemon.id ? .on : .off
        }

        shinyItem?.isEnabled = selectedPokemon.hasShiny
        shinyItem?.state = animator.isShiny ? .on : .off
        pauseItem?.title = isPaused ? "Fortsetzen" : "Pausieren"
        environmentReactionItem?.state = environmentReactionsEnabled ? .on : .off
        powerReactionItem?.state = powerReactionsEnabled ? .on : .off
        companionModeItem?.isHidden = !selectedPokemon.isCompanion
        for (mode, item) in companionModeItems {
            item.state = animator.companionMode == mode ? .on : .off
        }

        for (location, item) in locationItems {
            item.state = selectedLocation == location ? .on : .off
        }
        for (size, item) in sizeItems {
            item.state = selectedSize == size ? .on : .off
        }
        for (speed, item) in speedItems {
            item.state = selectedMovementSpeed == speed ? .on : .off
        }
        for (range, item) in rangeItems {
            item.state = selectedTravelRange == range ? .on : .off
        }

        switch launchAtLogin.status {
        case .enabled:
            launchAtLoginItem?.title = "Bei Anmeldung starten"
            launchAtLoginItem?.state = .on
        case .requiresApproval:
            launchAtLoginItem?.title = "Autostart freigeben …"
            launchAtLoginItem?.state = .mixed
        case .notFound, .notRegistered:
            launchAtLoginItem?.title = launchAtLogin.isInstalledInApplications
                ? "Bei Anmeldung starten"
                : "Autostart nach Installation"
            launchAtLoginItem?.state = .off
        @unknown default:
            launchAtLoginItem?.title = "Bei Anmeldung starten"
            launchAtLoginItem?.state = .off
        }

        for (mode, item) in modeItems {
            item.state = animator.playbackMode == mode ? .on : .off
            let isAvailable = isPlaybackModeAvailable(mode, for: selectedPokemon)
            item.isEnabled = isAvailable
            item.isHidden = mode != .automatic && !isAvailable
        }
    }

    private func isPlaybackModeAvailable(
        _ mode: PokemonAnimator.PlaybackMode,
        for pokemon: Pokemon
    ) -> Bool {
        let behaviors = pokemon.availableBehaviors
        switch mode {
        case .automatic:
            return true
        case .walk:
            return behaviors.contains("walk")
        case .idle:
            return behaviors.contains("idle")
        case .sleep:
            return behaviors.contains { $0.hasPrefix("sleep") }
        case .happy:
            return behaviors.contains { $0.hasPrefix("happy") }
        case .rainUmbrella:
            return behaviors.contains { $0 == "rain" || $0.hasPrefix("rain_") }
        case .fetchBall:
            return behaviors.contains("fetch_ball")
        case .jump:
            return behaviors.contains("jump")
        case .rollOver:
            return behaviors.contains("roll_over")
        case .sniffDiscover:
            return behaviors.contains("sniff_discover")
        case .tailWag:
            return behaviors.contains("tail_wag")
        case .treatCatch:
            return behaviors.contains("treat_catch")
        case .barkAlert:
            return behaviors.contains("bark_alert")
        case .chaseTail:
            return behaviors.contains("chase_tail")
        case .digging:
            return behaviors.contains("digging")
        case .highFive:
            return behaviors.contains("high_five")
        case .stretchYawn:
            return behaviors.contains("stretch_yawn")
        case .zoomies:
            return behaviors.contains("zoomies")
        case .sitTailSway:
            return behaviors.contains("sit_tail_sway")
        case .bananaEat:
            return behaviors.contains("banana_eat")
        case .climbVine:
            return behaviors.contains("climb_vine")
        case .swingVine:
            return behaviors.contains("swing_vine")
        case .dance:
            return behaviors.contains("dance")
        case .wave:
            return behaviors.contains("wave")
        case .clap:
            return behaviors.contains("clap")
        case .scratchHead:
            return behaviors.contains("scratch_head")
        case .coconutPlay:
            return behaviors.contains("coconut_play")
        case .sneeze:
            return behaviors.contains("sneeze")
        case .frontflip:
            return behaviors.contains("frontflip")
        }
    }

    @objc private func selectPokemon(_ sender: NSMenuItem) {
        guard
            let id = sender.representedObject as? String,
            let pokemon = library.pokemon(withID: id)
        else { return }

        selectedPokemon = pokemon
        animator.select(pokemon)
        if !isPlaybackModeAvailable(animator.playbackMode, for: pokemon) {
            animator.playbackMode = .automatic
        }
        updateMenuState()
    }

    @objc private func selectRandomPokemon() {
        guard let pokemon = library.pokemon.randomElement() else { return }
        selectedPokemon = pokemon
        animator.select(pokemon)
        if !isPlaybackModeAvailable(animator.playbackMode, for: pokemon) {
            animator.playbackMode = .automatic
        }
        updateMenuState()
    }

    @objc private func toggleShiny() {
        animator.isShiny.toggle()
        updateMenuState()
    }

    @objc private func selectPlaybackMode(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let mode = PokemonAnimator.PlaybackMode(rawValue: rawValue)
        else { return }

        animator.playbackMode = mode
        updateMenuState()
    }

    @objc private func selectCompanionMode(_ sender: NSMenuItem) {
        guard
            selectedPokemon.isCompanion,
            let rawValue = sender.representedObject as? String,
            let mode = PokemonAnimator.CompanionMode(rawValue: rawValue)
        else { return }

        animator.companionMode = mode
        animator.playbackMode = .automatic
        updateMenuState()
    }

    @objc private func selectLocation(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let location = PetLocation(rawValue: rawValue)
        else { return }

        selectedLocation = location
        UserDefaults.standard.set(location.rawValue, forKey: "petLocation")
        applyLocation()
        updateMenuState()
    }

    @objc private func selectSize(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let size = PetSizePreset(rawValue: rawValue)
        else { return }

        selectedSize = size
        UserDefaults.standard.set(size.rawValue, forKey: "petSize")
        animator.setDisplayDimension(size.dimension)
        if selectedLocation == .menuBar {
            statusItem.length = animator.statusItemLength
        }
        updateMenuState()
    }

    @objc private func selectMovementSpeed(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let speed = PetMovementSpeed(rawValue: rawValue)
        else { return }

        selectedMovementSpeed = speed
        UserDefaults.standard.set(speed.rawValue, forKey: "movementSpeed")
        applyMovementSettings()
        updateMenuState()
    }

    @objc private func selectTravelRange(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let range = PetTravelRange(rawValue: rawValue)
        else { return }

        selectedTravelRange = range
        UserDefaults.standard.set(range.rawValue, forKey: "travelRange")
        applyMovementSettings()
        updateMenuState()
    }

    @objc private func toggleLaunchAtLogin() {
        let shouldEnable: Bool
        switch launchAtLogin.status {
        case .enabled, .requiresApproval:
            shouldEnable = false
        default:
            shouldEnable = true
        }

        do {
            try launchAtLogin.setEnabled(shouldEnable)
            if launchAtLogin.status == .requiresApproval {
                launchAtLogin.openSystemSettings()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Autostart konnte nicht geändert werden"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        updateMenuState()
    }

    @objc private func togglePause() {
        isPaused.toggle()
        animator.setPaused(isPaused)
        updateMenuState()
    }

    @objc private func toggleEnvironmentReactions() {
        environmentReactionsEnabled.toggle()
        UserDefaults.standard.set(environmentReactionsEnabled, forKey: "environmentReactionsEnabled")
        if environmentReactionsEnabled {
            reactionController.start()
        } else {
            reactionController.stop()
        }
        updateMenuState()
    }

    @objc private func togglePowerReactions() {
        powerReactionsEnabled.toggle()
        UserDefaults.standard.set(powerReactionsEnabled, forKey: "powerReactionsEnabled")
        if powerReactionsEnabled {
            powerReactionController.start()
        } else {
            powerReactionController.stop()
        }
        updateMenuState()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func applyLocation() {
        if selectedLocation == .menuBar {
            overlayController.hide()
            animator.setDisplaysInStatusItem(true)
            statusItem.length = animator.statusItemLength
        } else {
            animator.setDisplaysInStatusItem(false)
            statusItem.length = 32
            overlayController.show(at: selectedLocation)
        }
    }

    private func applyMovementSettings() {
        animator.setMovementSettings(speed: selectedMovementSpeed, range: selectedTravelRange)
        overlayController.setMovementSettings(speed: selectedMovementSpeed, range: selectedTravelRange)
        if selectedLocation == .menuBar {
            statusItem.length = animator.statusItemLength
        }
    }

    private func applyContextCandidates() {
        let rainNames = Set(["rain", "rainy", "umbrella", "wet"])
        let rainCandidates = environmentCandidates.filter(rainNames.contains)
        let remainingEnvironmentCandidates = environmentCandidates.filter { !rainNames.contains($0) }
        animator.setContextCandidates(rainCandidates + powerCandidates + remainingEnvironmentCandidates)
    }
}
