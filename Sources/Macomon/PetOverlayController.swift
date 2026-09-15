import AppKit
import CoreGraphics

private final class ClickableImageView: NSImageView {
    var onMenuRequested: (() -> Void)?
    var onInteraction: (() -> Void)?
    var onDragEnded: ((NSPoint) -> Void)?
    private var dragStartMouseLocation: NSPoint?
    private var dragStartWindowOrigin: NSPoint?
    private(set) var isDraggingPet = false

    override func mouseDown(with event: NSEvent) {
        dragStartMouseLocation = NSEvent.mouseLocation
        dragStartWindowOrigin = window?.frame.origin
        isDraggingPet = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard
            let window,
            let startMouseLocation = dragStartMouseLocation,
            let startWindowOrigin = dragStartWindowOrigin
        else { return }

        let mouseLocation = NSEvent.mouseLocation
        let deltaX = mouseLocation.x - startMouseLocation.x
        let deltaY = mouseLocation.y - startMouseLocation.y
        if hypot(deltaX, deltaY) >= 3 {
            isDraggingPet = true
        }
        guard isDraggingPet else { return }

        window.setFrameOrigin(NSPoint(
            x: startWindowOrigin.x + deltaX,
            y: startWindowOrigin.y + deltaY
        ))
    }

    override func mouseUp(with event: NSEvent) {
        if isDraggingPet, let origin = window?.frame.origin {
            onDragEnded?(origin)
        } else {
            onInteraction?()
        }
        dragStartMouseLocation = nil
        dragStartWindowOrigin = nil
        isDraggingPet = false
    }

    override func rightMouseUp(with event: NSEvent) {
        onMenuRequested?()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }
}

final class PetOverlayController {
    private struct Track {
        let minimumX: CGFloat
        let maximumX: CGFloat
        let y: CGFloat
    }

    private let panel: NSPanel
    private let imageView: ClickableImageView
    private var location: PetLocation = .menuBar
    private var currentTrack: Track?
    private var movementDirection: CGFloat = 1
    private var lastUpdateTime = ProcessInfo.processInfo.systemUptime
    private var lastTrackUpdateTime: TimeInterval = 0
    private var spaceChangeObserver: NSObjectProtocol?
    private var screenChangeObserver: NSObjectProtocol?
    private var movementSpeed: PetMovementSpeed = .normal
    private var travelRange: PetTravelRange = .medium

    var onDirectionChange: ((CGFloat) -> Void)?
    var onClick: (() -> Void)? {
        didSet { imageView.onMenuRequested = onClick }
    }
    var onInteraction: (() -> Void)? {
        didSet { imageView.onInteraction = onInteraction }
    }
    var onDragEnded: ((NSPoint) -> Void)?

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 32, height: 32),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        imageView = ClickableImageView(frame: panel.contentView?.bounds ?? .zero)

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.isExcludedFromWindowsMenu = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = imageView
        imageView.imageAlignment = .alignCenter
        imageView.imageScaling = .scaleNone
        imageView.onDragEnded = { [weak self] position in
            self?.finishDragging(at: position)
        }

        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.restoreAfterSpaceChange()
        }
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.restoreAfterSpaceChange()
        }
    }

    deinit {
        if let spaceChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceChangeObserver)
        }
        if let screenChangeObserver {
            NotificationCenter.default.removeObserver(screenChangeObserver)
        }
    }

    func show(at location: PetLocation) {
        guard location != .menuBar else {
            hide()
            return
        }

        self.location = location
        lastUpdateTime = ProcessInfo.processInfo.systemUptime
        lastTrackUpdateTime = 0
        updateTrack(force: true)

        if let track = currentTrack {
            let centeredX = track.minimumX + (track.maximumX - track.minimumX) / 2
            panel.setFrameOrigin(NSPoint(x: centeredX, y: track.y))
        }

        panel.orderFrontRegardless()
    }

    func hide() {
        location = .menuBar
        panel.orderOut(nil)
    }

    func setMovementSettings(speed: PetMovementSpeed, range: PetTravelRange) {
        movementSpeed = speed
        travelRange = range
        lastTrackUpdateTime = 0
        updateTrack(force: true)
    }

    func present(_ menu: NSMenu) {
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: imageView.bounds.midX, y: imageView.bounds.minY),
            in: imageView
        )
    }

    func update(image: NSImage, behavior: String, direction: CGFloat) {
        imageView.image = image
        resizePanel(to: image.size)

        guard location != .menuBar else { return }
        guard !imageView.isDraggingPet else { return }
        movementDirection = direction < 0 ? -1 : 1

        let now = ProcessInfo.processInfo.systemUptime
        let delta = min(0.1, max(0, now - lastUpdateTime))
        lastUpdateTime = now
        updateTrack(force: now - lastTrackUpdateTime > 0.25)

        guard let track = currentTrack else { return }
        var origin = panel.frame.origin
        origin.y = track.y

        let canMove = track.maximumX - track.minimumX > 1
        if behavior == "walk", canMove {
            origin.x += movementDirection
                * max(28, image.size.width * 1.25)
                * movementSpeed.multiplier
                * delta
        }

        if !canMove {
            origin.x = track.minimumX
        } else if origin.x >= track.maximumX {
            origin.x = track.maximumX
            changeDirection(to: -1)
        } else if origin.x <= track.minimumX {
            origin.x = track.minimumX
            changeDirection(to: 1)
        }

        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
    }

    private func resizePanel(to size: NSSize) {
        guard panel.frame.size != size else { return }
        let origin = panel.frame.origin
        panel.setContentSize(size)
        imageView.frame = NSRect(origin: .zero, size: size)
        panel.setFrameOrigin(origin)
        lastTrackUpdateTime = 0
    }

    private func updateTrack(force: Bool) {
        guard force else { return }
        lastTrackUpdateTime = ProcessInfo.processInfo.systemUptime

        switch location {
        case .menuBar:
            currentTrack = nil
        case .notch:
            panel.level = .statusBar
            currentTrack = notchTrack()
        case .desktop:
            panel.level = .floating
            currentTrack = desktopTrack()
        case .activeWindow:
            panel.level = .floating
            currentTrack = activeWindowTrack() ?? fallbackWindowTrack()
        case .free:
            panel.level = .floating
            currentTrack = freeTrack()
        }

        if let track = currentTrack {
            var origin = panel.frame.origin
            origin.x = min(track.maximumX, max(track.minimumX, origin.x))
            origin.y = track.y
            panel.setFrameOrigin(origin)
        }
    }

    private func notchTrack() -> Track? {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return nil }
        let dimension = panel.frame.width
        let y = screen.frame.maxY - panel.frame.height

        let preferredTrackWidth = max(travelRange.overlayDistance, dimension * 2)

        if let leftArea = screen.auxiliaryTopLeftArea,
           !leftArea.isEmpty,
           leftArea.width >= dimension + 24 {
            let maximumX = leftArea.maxX - dimension - 12
            let minimumX = max(leftArea.minX + 12, maximumX - preferredTrackWidth)
            return Track(minimumX: minimumX, maximumX: max(minimumX, maximumX), y: y)
        }

        if let rightArea = screen.auxiliaryTopRightArea,
           !rightArea.isEmpty,
           rightArea.width >= dimension + 24 {
            let minimumX = rightArea.minX + 12
            let maximumX = min(rightArea.maxX - dimension - 12, minimumX + preferredTrackWidth)
            return Track(minimumX: minimumX, maximumX: max(minimumX, maximumX), y: y)
        }

        let trackWidth = min(screen.frame.width, max(260, dimension * 6))
        let minimumX = screen.frame.midX - trackWidth / 2
        let maximumX = screen.frame.midX + trackWidth / 2 - dimension
        return Track(minimumX: minimumX, maximumX: max(minimumX, maximumX), y: y)
    }

    private func desktopTrack() -> Track? {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return nil }
        let minimumX = screen.visibleFrame.minX + 8
        let maximumX = screen.visibleFrame.maxX - panel.frame.width - 8
        let y = screen.visibleFrame.minY + 6
        return limitedTrack(minimumX: minimumX, maximumX: maximumX, y: y)
    }

    private func fallbackWindowTrack() -> Track? {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return nil }
        let minimumX = screen.visibleFrame.minX + 80
        let maximumX = screen.visibleFrame.maxX - panel.frame.width - 24
        let y = screen.visibleFrame.maxY - panel.frame.height + 2
        return limitedTrack(minimumX: minimumX, maximumX: maximumX, y: y)
    }

    private func freeTrack() -> Track? {
        let defaults = UserDefaults.standard
        let point: NSPoint
        if defaults.object(forKey: "freePositionX") != nil,
           defaults.object(forKey: "freePositionY") != nil {
            point = NSPoint(
                x: defaults.double(forKey: "freePositionX"),
                y: defaults.double(forKey: "freePositionY")
            )
        } else if let screen = NSScreen.main ?? NSScreen.screens.first {
            point = NSPoint(
                x: screen.visibleFrame.midX - panel.frame.width / 2,
                y: screen.visibleFrame.midY - panel.frame.height / 2
            )
        } else {
            return nil
        }

        let screen = NSScreen.screens.first { $0.frame.contains(point) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return nil }

        let travelWidth = max(travelRange.overlayDistance, panel.frame.width * 2)
        let allowedMinimumX = screen.visibleFrame.minX + 8
        let allowedMaximumX = screen.visibleFrame.maxX - panel.frame.width - 8
        var minimumX = max(allowedMinimumX, point.x - travelWidth / 2)
        var maximumX = min(allowedMaximumX, point.x + travelWidth / 2)

        if maximumX - minimumX < travelWidth {
            if minimumX == allowedMinimumX {
                maximumX = min(allowedMaximumX, minimumX + travelWidth)
            } else if maximumX == allowedMaximumX {
                minimumX = max(allowedMinimumX, maximumX - travelWidth)
            }
        }

        return Track(minimumX: minimumX, maximumX: max(minimumX, maximumX), y: point.y)
    }

    private func activeWindowTrack() -> Track? {
        guard
            let application = NSWorkspace.shared.frontmostApplication,
            application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
            let windowInfo = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
            ) as? [[String: Any]],
            let mainScreenTop = NSScreen.screens.first?.frame.maxY
        else { return nil }

        let ownerPIDKey = kCGWindowOwnerPID as String
        let layerKey = kCGWindowLayer as String
        let boundsKey = kCGWindowBounds as String

        for window in windowInfo {
            guard
                let ownerPID = window[ownerPIDKey] as? Int,
                ownerPID == application.processIdentifier,
                (window[layerKey] as? Int) == 0,
                let boundsDictionary = window[boundsKey] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
                bounds.width > 240,
                bounds.height > 120
            else { continue }

            let minimumX = bounds.minX + 80
            let maximumX = bounds.maxX - panel.frame.width - 24
            let topEdge = mainScreenTop - bounds.minY
            let y = topEdge - panel.frame.height + 2
            return limitedTrack(minimumX: minimumX, maximumX: maximumX, y: y)
        }

        return nil
    }

    private func limitedTrack(minimumX: CGFloat, maximumX: CGFloat, y: CGFloat) -> Track {
        let safeMaximumX = max(minimumX, maximumX)
        let availableWidth = safeMaximumX - minimumX
        let width = min(availableWidth, max(travelRange.overlayDistance, panel.frame.width * 2))
        let allowedCenter = minimumX + availableWidth / 2
        let preferredMinimum = allowedCenter - width / 2
        let limitedMinimum = min(safeMaximumX - width, max(minimumX, preferredMinimum))
        return Track(minimumX: limitedMinimum, maximumX: limitedMinimum + width, y: y)
    }

    private func changeDirection(to direction: CGFloat) {
        movementDirection = direction
        onDirectionChange?(direction)
    }

    private func finishDragging(at position: NSPoint) {
        location = .free
        UserDefaults.standard.set(position.x, forKey: "freePositionX")
        UserDefaults.standard.set(position.y, forKey: "freePositionY")
        currentTrack = freeTrack()
        onDragEnded?(position)
    }

    private func restoreAfterSpaceChange() {
        guard location != .menuBar else { return }
        lastTrackUpdateTime = 0
        updateTrack(force: true)
        panel.orderFrontRegardless()

        DispatchQueue.main.async { [weak self] in
            guard let self, self.location != .menuBar else { return }
            self.updateTrack(force: true)
            self.panel.orderFrontRegardless()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.location != .menuBar else { return }
            self.updateTrack(force: true)
            self.panel.orderFrontRegardless()
        }
    }
}
