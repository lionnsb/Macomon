import AppKit

final class PokemonAnimator {
    enum PlaybackMode: String {
        case automatic
        case idle
        case walk
        case sleep
        case happy
        case rainUmbrella
        case fetchBall
        case jump
        case rollOver
        case sniffDiscover
        case tailWag
        case treatCatch
        case barkAlert
        case chaseTail
        case digging
        case highFive
        case stretchYawn
        case zoomies
        case sitTailSway
        case bananaEat
        case climbVine
        case swingVine
        case dance
        case wave
        case clap
        case scratchHead
        case coconutPlay
        case sneeze
        case frontflip
    }

    enum CompanionMode: String, CaseIterable {
        case balanced
        case randomAll
        case calm
        case playful
        case active

        func candidateBehaviors(from availableBehaviors: [String]) -> [String] {
            let regularBehaviors = availableBehaviors.filter { !Self.isContextOnlyBehavior($0) }
            let eligibleBehaviors = regularBehaviors.isEmpty ? availableBehaviors : regularBehaviors
            let preferredBehaviors: [String]
            switch self {
            case .balanced, .randomAll:
                return eligibleBehaviors
            case .calm:
                preferredBehaviors = [
                    "idle", "sleep_zzz", "tail_wag", "sniff_discover",
                    "stretch_yawn", "sit_tail_sway", "scratch_head", "walk"
                ]
            case .playful:
                preferredBehaviors = [
                    "happy_hearts", "tail_wag", "jump", "roll_over",
                    "fetch_ball", "treat_catch", "high_five", "chase_tail",
                    "zoomies", "digging", "banana_eat", "climb_vine",
                    "swing_vine", "dance", "wave", "clap", "coconut_play",
                    "sneeze", "frontflip", "walk"
                ]
            case .active:
                preferredBehaviors = [
                    "walk", "jump", "fetch_ball", "sniff_discover",
                    "treat_catch", "happy_hearts", "bark_alert", "chase_tail",
                    "digging", "high_five", "zoomies", "climb_vine",
                    "swing_vine", "dance", "clap", "coconut_play", "frontflip"
                ]
            }

            let candidates = preferredBehaviors.filter(eligibleBehaviors.contains)
            return candidates.isEmpty ? eligibleBehaviors : candidates
        }

        private static func isContextOnlyBehavior(_ behavior: String) -> Bool {
            behavior == "rain" || behavior.hasPrefix("rain_")
        }
    }

    typealias FrameHandler = (_ image: NSImage, _ behavior: String, _ direction: CGFloat) -> Void

    private let maximumStatusSpriteDimension: CGFloat = 30
    private let tickInterval: TimeInterval = 1.0 / 30.0

    private weak var button: NSStatusBarButton?
    private var timer: Timer?
    private var pokemon: Pokemon
    private var animation: GIFAnimation?
    private var loadedAnimationKey: String?
    private var frameIndex = 0
    private var frameElapsed: TimeInterval = 0
    private var behaviorElapsed: TimeInterval = 0
    private var behaviorDuration: TimeInterval = 4
    private var horizontalPosition: CGFloat = 20
    private var direction: CGFloat = 1
    private var displaysInStatusItem = true
    private var contextCandidates: [String] = []
    private var contextBehavior: String?
    private var temporaryInteractionBehavior: String?
    private var movementSpeed: PetMovementSpeed = .normal
    private var travelRange: PetTravelRange = .medium
    private(set) var displayDimension: CGFloat

    var onFrame: FrameHandler?

    var statusItemLength: CGFloat {
        statusSpriteDimension + statusTravelDistance + 4
    }

    private var statusTravelDistance: CGFloat {
        travelRange.statusItemDistance
    }

    var isShiny: Bool {
        didSet {
            if isShiny && !pokemon.hasShiny { isShiny = false }
            loadedAnimationKey = nil
            UserDefaults.standard.set(isShiny, forKey: "isShiny")
        }
    }

    var playbackMode: PlaybackMode = .automatic {
        didSet {
            resetBehaviorForPlaybackMode()
            UserDefaults.standard.set(playbackMode.rawValue, forKey: "playbackMode")
        }
    }

    var companionMode: CompanionMode = .balanced {
        didSet {
            resetBehaviorForPlaybackMode()
            UserDefaults.standard.set(companionMode.rawValue, forKey: "companionMode")
        }
    }

    private(set) var currentBehavior = "walk"

    private var statusSpriteDimension: CGFloat {
        switch displayDimension {
        case ..<28: return 16
        case ..<40: return 21
        case ..<56: return 26
        default: return maximumStatusSpriteDimension
        }
    }

    private var statusCanvasSize: NSSize {
        NSSize(
            width: statusSpriteDimension + statusTravelDistance,
            height: statusSpriteDimension
        )
    }

    init(button: NSStatusBarButton, pokemon: Pokemon, displayDimension: CGFloat) {
        self.button = button
        self.pokemon = pokemon
        self.displayDimension = displayDimension
        self.isShiny = UserDefaults.standard.bool(forKey: "isShiny") && pokemon.hasShiny
        if let savedMode = UserDefaults.standard.string(forKey: "playbackMode"),
           let mode = PlaybackMode(rawValue: savedMode) {
            playbackMode = mode
        }
        if let savedCompanionMode = UserDefaults.standard.string(forKey: "companionMode"),
           let mode = CompanionMode(rawValue: savedCompanionMode) {
            companionMode = mode
        }

        currentBehavior = behaviorForMode()
        behaviorDuration = nextBehaviorDuration()
        configureButton()
        start()
    }

    deinit {
        timer?.invalidate()
    }

    func select(_ pokemon: Pokemon) {
        self.pokemon = pokemon
        if isShiny && !pokemon.hasShiny { isShiny = false }
        resetBehaviorForPlaybackMode()
        frameIndex = 0
        frameElapsed = 0
        UserDefaults.standard.set(pokemon.id, forKey: "selectedPokemon")
        button?.setAccessibilityLabel("Macomon: \(pokemon.displayName)")
        render()
    }

    func setPaused(_ paused: Bool) {
        timer?.fireDate = paused ? .distantFuture : .distantPast
    }

    func setDisplayDimension(_ dimension: CGFloat) {
        displayDimension = dimension
        horizontalPosition = min(horizontalPosition, statusTravelDistance)
        render()
    }

    func setMovementSettings(speed: PetMovementSpeed, range: PetTravelRange) {
        movementSpeed = speed
        travelRange = range
        horizontalPosition = min(horizontalPosition, statusTravelDistance)
        render()
    }

    func setDisplaysInStatusItem(_ displays: Bool) {
        displaysInStatusItem = displays
        configureButton()
        render()
    }

    func setDirection(_ newDirection: CGFloat) {
        let normalizedDirection: CGFloat = newDirection < 0 ? -1 : 1
        guard normalizedDirection != direction else { return }
        direction = normalizedDirection
        loadedAnimationKey = nil
    }

    func setContextCandidates(_ candidates: [String]) {
        guard candidates != contextCandidates else { return }
        contextCandidates = candidates
        guard playbackMode == .automatic else { return }
        guard temporaryInteractionBehavior == nil else { return }

        let newContextBehavior = matchingContextBehavior()
        guard newContextBehavior != contextBehavior else { return }
        contextBehavior = newContextBehavior
        currentBehavior = newContextBehavior ?? behaviorForMode()
        behaviorElapsed = 0
        behaviorDuration = nextBehaviorDuration()
        loadedAnimationKey = nil
    }

    func refresh() {
        render()
    }

    func triggerInteraction() {
        let candidates = Self.interactionBehaviors(from: pokemon.availableBehaviors)
        guard let behavior = candidates.randomElement() else { return }

        temporaryInteractionBehavior = behavior
        currentBehavior = behavior
        behaviorElapsed = 0
        behaviorDuration = Double.random(in: 2.2...3.8)
        loadedAnimationKey = nil
    }

    static func interactionBehaviors(from availableBehaviors: [String]) -> [String] {
        let preferredBehaviors = [
            "high_five", "happy_hearts", "tail_wag", "wave", "clap", "dance",
            "scratch_head", "jump", "bark_alert", "idle"
        ]
        return preferredBehaviors.filter(availableBehaviors.contains)
    }

    private func configureButton() {
        if displaysInStatusItem {
            button?.title = ""
            button?.imagePosition = .imageOnly
            button?.imageScaling = .scaleNone
        } else {
            if let url = ResourceLocator.dogMarkURL(),
               let dogMark = NSImage(contentsOf: url) {
                dogMark.size = NSSize(width: 19, height: 19)
                dogMark.isTemplate = true
                button?.image = dogMark
                button?.title = ""
                button?.imagePosition = .imageOnly
                button?.imageScaling = .scaleProportionallyDown
            } else {
                button?.image = nil
                button?.title = "🐾"
                button?.imagePosition = .noImage
            }
        }
        button?.setAccessibilityLabel("Macomon: \(pokemon.displayName)")
    }

    private func start() {
        loadAnimationIfNeeded()
        render()

        let timer = Timer(timeInterval: tickInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        behaviorElapsed += tickInterval

        if temporaryInteractionBehavior != nil,
           behaviorElapsed >= behaviorDuration {
            temporaryInteractionBehavior = nil
            resetBehaviorForPlaybackMode()
        } else if playbackMode == .automatic,
           contextBehavior == nil,
           behaviorElapsed >= behaviorDuration {
            chooseNextAutomaticBehavior()
        }

        if displaysInStatusItem && currentBehavior == "walk" {
            horizontalPosition += direction * 13 * movementSpeed.multiplier * tickInterval
            if horizontalPosition >= statusTravelDistance {
                horizontalPosition = statusTravelDistance
                setDirection(-1)
            } else if horizontalPosition <= 0 {
                horizontalPosition = 0
                setDirection(1)
            }
        }

        loadAnimationIfNeeded()
        advanceFrame()
        render()
    }

    private func advanceFrame() {
        guard let animation, !animation.frames.isEmpty else { return }
        frameElapsed += tickInterval
        let duration = animation.durations[min(frameIndex, animation.durations.count - 1)]
        if frameElapsed >= duration {
            frameElapsed -= duration
            frameIndex = (frameIndex + 1) % animation.frames.count
        }
    }

    private func loadAnimationIfNeeded() {
        let variant = isShiny ? "shiny" : "default"
        let facingLeft = direction < 0
        let key = "\(pokemon.id)|\(variant)|\(currentBehavior)|\(facingLeft)"
        guard key != loadedAnimationKey else { return }

        let requestedBehavior = pokemon.availableBehaviors.contains(currentBehavior)
            ? currentBehavior
            : pokemon.availableBehaviors.first ?? "idle"

        guard let url = pokemon.animationURL(
            variant: variant,
            behavior: requestedBehavior,
            facingLeft: facingLeft
        ) else { return }

        animation = GIFAnimation.load(from: url)
        loadedAnimationKey = key
        frameIndex = 0
        frameElapsed = 0
    }

    private func render() {
        guard let animation, !animation.frames.isEmpty else { return }

        let frame = animation.frames[min(frameIndex, animation.frames.count - 1)]
        let needsMirroring = direction < 0 && !pokemon.hasDedicatedLeftAnimation(
            variant: isShiny ? "shiny" : "default",
            behavior: currentBehavior
        )
        let overlaySprite = renderedSprite(
            frame: frame,
            dimension: displayDimension,
            mirrored: needsMirroring
        )
        onFrame?(overlaySprite, currentBehavior, direction)

        guard displaysInStatusItem else { return }
        let statusSprite = renderedSprite(
            frame: frame,
            dimension: statusSpriteDimension,
            mirrored: needsMirroring
        )
        let canvas = NSImage(size: statusCanvasSize)
        canvas.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .none
        statusSprite.draw(
            in: NSRect(
                x: horizontalPosition.rounded(),
                y: 0,
                width: statusSpriteDimension,
                height: statusSpriteDimension
            ),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        canvas.unlockFocus()
        canvas.isTemplate = false
        button?.image = canvas
    }

    private func renderedSprite(frame: CGImage, dimension: CGFloat, mirrored: Bool) -> NSImage {
        let sourceImage = NSImage(
            cgImage: frame,
            size: NSSize(width: frame.width, height: frame.height)
        )
        let image = NSImage(size: NSSize(width: dimension, height: dimension))
        image.lockFocus()

        if let context = NSGraphicsContext.current {
            context.imageInterpolation = .none
            let destination = NSRect(x: 0, y: 0, width: dimension, height: dimension)
            if mirrored {
                context.cgContext.saveGState()
                context.cgContext.translateBy(x: dimension, y: 0)
                context.cgContext.scaleBy(x: -1, y: 1)
                sourceImage.draw(in: destination, from: .zero, operation: .sourceOver, fraction: 1)
                context.cgContext.restoreGState()
            } else {
                sourceImage.draw(in: destination, from: .zero, operation: .sourceOver, fraction: 1)
            }
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private func behaviorForMode() -> String {
        switch playbackMode {
        case .automatic:
            if pokemon.isCompanion {
                let candidates = companionMode.candidateBehaviors(from: pokemon.availableBehaviors)
                switch companionMode {
                case .calm:
                    return candidates.first(where: { $0 == "idle" }) ?? candidates.first ?? "idle"
                case .playful:
                    return candidates.first(where: { $0 == "happy_hearts" }) ?? candidates.first ?? "idle"
                case .active:
                    return candidates.first(where: { $0 == "walk" }) ?? candidates.first ?? "idle"
                case .balanced, .randomAll:
                    return candidates.randomElement() ?? "idle"
                }
            }
            return pokemon.availableBehaviors.contains("walk") ? "walk" : pokemon.availableBehaviors.first ?? "idle"
        case .idle:
            return pokemon.availableBehaviors.contains("idle") ? "idle" : pokemon.availableBehaviors.first ?? "idle"
        case .walk:
            return pokemon.availableBehaviors.contains("walk") ? "walk" : pokemon.availableBehaviors.first ?? "idle"
        case .sleep:
            return pokemon.availableBehaviors.first { $0.hasPrefix("sleep") }
                ?? pokemon.availableBehaviors.first { $0 == "idle" }
                ?? pokemon.availableBehaviors.first
                ?? "idle"
        case .happy:
            return pokemon.availableBehaviors.first { $0.hasPrefix("happy") }
                ?? pokemon.availableBehaviors.first { $0 == "idle" }
                ?? pokemon.availableBehaviors.first
                ?? "idle"
        case .rainUmbrella:
            return pokemon.availableBehaviors.first { $0 == "rain" || $0.hasPrefix("rain_") }
                ?? behavior(named: "idle")
        case .fetchBall:
            return behavior(named: "fetch_ball")
        case .jump:
            return behavior(named: "jump")
        case .rollOver:
            return behavior(named: "roll_over")
        case .sniffDiscover:
            return behavior(named: "sniff_discover")
        case .tailWag:
            return behavior(named: "tail_wag")
        case .treatCatch:
            return behavior(named: "treat_catch")
        case .barkAlert:
            return behavior(named: "bark_alert")
        case .chaseTail:
            return behavior(named: "chase_tail")
        case .digging:
            return behavior(named: "digging")
        case .highFive:
            return behavior(named: "high_five")
        case .stretchYawn:
            return behavior(named: "stretch_yawn")
        case .zoomies:
            return behavior(named: "zoomies")
        case .sitTailSway:
            return behavior(named: "sit_tail_sway")
        case .bananaEat:
            return behavior(named: "banana_eat")
        case .climbVine:
            return behavior(named: "climb_vine")
        case .swingVine:
            return behavior(named: "swing_vine")
        case .dance:
            return behavior(named: "dance")
        case .wave:
            return behavior(named: "wave")
        case .clap:
            return behavior(named: "clap")
        case .scratchHead:
            return behavior(named: "scratch_head")
        case .coconutPlay:
            return behavior(named: "coconut_play")
        case .sneeze:
            return behavior(named: "sneeze")
        case .frontflip:
            return behavior(named: "frontflip")
        }
    }

    private func behavior(named name: String) -> String {
        pokemon.availableBehaviors.first { $0 == name }
            ?? pokemon.availableBehaviors.first { $0 == "idle" }
            ?? pokemon.availableBehaviors.first
            ?? "idle"
    }

    private func resetBehaviorForPlaybackMode() {
        temporaryInteractionBehavior = nil
        contextBehavior = playbackMode == .automatic ? matchingContextBehavior() : nil
        currentBehavior = contextBehavior ?? behaviorForMode()
        behaviorElapsed = 0
        behaviorDuration = nextBehaviorDuration()
        loadedAnimationKey = nil
    }

    private func matchingContextBehavior() -> String? {
        pokemon.behavior(matching: contextCandidates)
    }

    private func chooseNextAutomaticBehavior() {
        let behaviors = pokemon.availableBehaviors
        guard !behaviors.isEmpty else { return }

        if pokemon.isCompanion {
            currentBehavior = nextCompanionBehavior(from: behaviors)
        } else if behaviors.contains("idle"), behaviors.contains("walk") {
            if currentBehavior == "walk" {
                currentBehavior = behaviors.filter { $0 != "walk" }.randomElement() ?? "idle"
            } else {
                currentBehavior = "walk"
            }
        } else {
            currentBehavior = behaviors.randomElement() ?? behaviors[0]
        }

        behaviorElapsed = 0
        behaviorDuration = nextBehaviorDuration()
        loadedAnimationKey = nil
    }

    private func nextCompanionBehavior(from behaviors: [String]) -> String {
        let candidates = companionMode.candidateBehaviors(from: behaviors)
        guard !candidates.isEmpty else { return currentBehavior }

        if companionMode == .balanced,
           candidates.contains("idle"),
           candidates.contains("walk") {
            if currentBehavior == "walk" {
                return candidates.filter { $0 != "walk" }.randomElement() ?? "idle"
            }
            return "walk"
        }

        let weightedCandidates: [String]
        switch companionMode {
        case .balanced, .randomAll:
            weightedCandidates = candidates
        case .calm:
            weightedCandidates = weighted(
                candidates,
                weights: [
                    "idle": 4, "sleep_zzz": 3, "tail_wag": 2,
                    "sniff_discover": 2, "stretch_yawn": 2,
                    "sit_tail_sway": 3, "scratch_head": 1, "walk": 1
                ]
            )
        case .playful:
            weightedCandidates = weighted(
                candidates,
                weights: [
                    "happy_hearts": 2, "tail_wag": 2, "jump": 2, "roll_over": 1,
                    "fetch_ball": 2, "treat_catch": 2, "high_five": 2,
                    "chase_tail": 2, "zoomies": 3, "digging": 1,
                    "banana_eat": 1, "climb_vine": 2, "swing_vine": 2,
                    "dance": 2, "wave": 1, "clap": 2, "coconut_play": 2,
                    "sneeze": 1, "frontflip": 2, "walk": 1
                ]
            )
        case .active:
            weightedCandidates = weighted(
                candidates,
                weights: [
                    "walk": 4, "jump": 2, "fetch_ball": 2,
                    "sniff_discover": 2, "treat_catch": 1, "happy_hearts": 1,
                    "bark_alert": 1, "chase_tail": 2, "digging": 2,
                    "high_five": 1, "zoomies": 3, "climb_vine": 2,
                    "swing_vine": 2, "dance": 2, "clap": 1,
                    "coconut_play": 1, "frontflip": 3
                ]
            )
        }

        let alternatives = weightedCandidates.filter { $0 != currentBehavior }
        return (alternatives.isEmpty ? weightedCandidates : alternatives).randomElement()
            ?? candidates[0]
    }

    private func weighted(_ behaviors: [String], weights: [String: Int]) -> [String] {
        behaviors.flatMap { behavior in
            Array(repeating: behavior, count: max(1, weights[behavior] ?? 1))
        }
    }

    private func nextBehaviorDuration() -> TimeInterval {
        if pokemon.isCompanion && playbackMode == .automatic {
            switch companionMode {
            case .calm:
                if currentBehavior.hasPrefix("sleep") { return Double.random(in: 7...12) }
                if currentBehavior == "walk" { return Double.random(in: 4...7) }
                return Double.random(in: 4...8)
            case .playful:
                return currentBehavior == "walk"
                    ? Double.random(in: 3...6)
                    : Double.random(in: 2...4)
            case .active:
                return currentBehavior == "walk"
                    ? Double.random(in: 5...9)
                    : Double.random(in: 1.5...3.5)
            case .balanced, .randomAll:
                break
            }
        }

        switch currentBehavior {
        case "walk":
            return Double.random(in: 4...8)
        case let behavior where behavior.hasPrefix("sleep"):
            return Double.random(in: 5...9)
        default:
            return Double.random(in: 2...5)
        }
    }
}
