import AppKit
import SwiftUI

/// A borderless, always-on-desktop window that displays a photo.
class DesktopPhotoWindow: NSWindow {
    var photoId: UUID?
    var onLockToggle: (() -> Void)?
    var onRemove: (() -> Void)?
    var onResize: ((CGFloat) -> Void)?

    init() {
        super.init(
            contentRect: NSRect(x: 100, y: 100, width: 300, height: 300),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func showPhoto(_ image: NSImage, baseWidth: CGFloat = 300, locked: Bool = false) {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return }

        let aspectRatio = imageSize.width / imageSize.height
        let w = baseWidth
        let h = w / aspectRatio

        let container = DraggablePhotoView(
            frame: NSRect(x: 0, y: 0, width: w, height: h),
            image: image,
            locked: locked
        )
        container.onLockToggle = { [weak self] in self?.onLockToggle?() }
        container.onRemove = { [weak self] in self?.onRemove?() }
        container.onResizeFinished = { [weak self] newWidth in self?.onResize?(newWidth) }

        contentView = container
        setContentSize(NSSize(width: w, height: h))
        makeKeyAndOrderFront(nil)
    }

    func hidePhoto() { orderOut(nil) }

    func setLocked(_ locked: Bool) {
        (contentView as? DraggablePhotoView)?.isLocked = locked
    }

    func resizeTo(width: CGFloat) {
        guard let container = contentView as? DraggablePhotoView,
              let image = container.photoImage else { return }
        let ar = image.size.width / image.size.height
        let h = width / ar
        let newFrame = NSRect(x: frame.origin.x, y: frame.origin.y, width: width, height: h)
        setFrame(newFrame, display: true, animate: true)
        container.updateLayout(NSSize(width: width, height: h))
    }
}

// MARK: - Resize Handle

private enum DragMode {
    case none
    case move
    case resizeTopLeft, resizeTopRight, resizeBottomLeft, resizeBottomRight
}

// MARK: - Draggable Photo View

class DraggablePhotoView: NSView {
    let imageView: NSImageView
    var photoImage: NSImage? { imageView.image }
    var isLocked = false

    var onLockToggle: (() -> Void)?
    var onRemove: (() -> Void)?
    var onResizeFinished: ((CGFloat) -> Void)?

    private var dragMode: DragMode = .none
    private var initialMouse: NSPoint = .zero
    private var anchorPoint: NSPoint = .zero   // the fixed corner (screen coords)
    private var aspectRatio: CGFloat = 1.0
    private let handleZone: CGFloat = 12
    private let minSize: CGFloat = 80

    init(frame: NSRect, image: NSImage, locked: Bool) {
        imageView = NSImageView(frame: NSRect(origin: .zero, size: frame.size))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 16
        imageView.layer?.masksToBounds = true
        imageView.layer?.cornerCurve = .continuous
        self.isLocked = locked
        self.aspectRatio = image.size.width / image.size.height

        super.init(frame: frame)

        wantsLayer = true
        shadow = NSShadow()
        shadow?.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow?.shadowOffset = NSSize(width: 0, height: -2)
        shadow?.shadowBlurRadius = 10

        addSubview(imageView)

        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .mouseMoved, .inVisibleRect, .mouseEnteredAndExited],
            owner: self
        ))
    }

    required init?(coder: NSCoder) { fatalError() }

    func updateLayout(_ size: NSSize) {
        frame = NSRect(origin: .zero, size: size)
        imageView.frame = bounds
        // Keep corner radius reasonable
        imageView.layer?.cornerRadius = min(16, min(size.width, size.height) * 0.08)
    }

    // MARK: - Hit zones

    private func modeAt(_ localPoint: NSPoint) -> DragMode {
        let h = handleZone
        let w = bounds.width
        let ht = bounds.height

        let nearLeft = localPoint.x < h
        let nearRight = localPoint.x > w - h
        let nearBottom = localPoint.y < h
        let nearTop = localPoint.y > ht - h

        if nearBottom && nearLeft { return .resizeBottomLeft }
        if nearBottom && nearRight { return .resizeBottomRight }
        if nearTop && nearLeft { return .resizeTopLeft }
        if nearTop && nearRight { return .resizeTopRight }
        return .move
    }

    // MARK: - Cursor

    override func mouseMoved(with event: NSEvent) {
        if isLocked { NSCursor.arrow.set(); return }
        let p = convert(event.locationInWindow, from: nil)
        switch modeAt(p) {
        case .resizeTopLeft, .resizeBottomRight:
            NSCursor.crosshair.set()
        case .resizeTopRight, .resizeBottomLeft:
            NSCursor.crosshair.set()
        case .move:
            NSCursor.openHand.set()
        case .none:
            NSCursor.arrow.set()
        }
    }

    override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }

    // MARK: - Mouse events

    override func mouseDown(with event: NSEvent) {
        if isLocked { return }

        guard let win = window else { return }
        let p = convert(event.locationInWindow, from: nil)
        dragMode = modeAt(p)
        initialMouse = NSEvent.mouseLocation

        let f = win.frame
        // Set anchor = the corner OPPOSITE to the one being dragged
        switch dragMode {
        case .resizeBottomRight: anchorPoint = NSPoint(x: f.minX, y: f.maxY) // top-left fixed
        case .resizeBottomLeft:  anchorPoint = NSPoint(x: f.maxX, y: f.maxY) // top-right fixed
        case .resizeTopRight:    anchorPoint = NSPoint(x: f.minX, y: f.minY) // bottom-left fixed
        case .resizeTopLeft:     anchorPoint = NSPoint(x: f.maxX, y: f.minY) // bottom-right fixed
        default: break
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if isLocked { return }
        guard let win = window else { return }

        let mouse = NSEvent.mouseLocation

        switch dragMode {
        case .move:
            let dx = mouse.x - initialMouse.x
            let dy = mouse.y - initialMouse.y
            let oldOrigin = win.frame.origin
            win.setFrameOrigin(NSPoint(
                x: oldOrigin.x + dx,
                y: oldOrigin.y + dy
            ))
            initialMouse = mouse

        case .resizeBottomRight:
            // Anchor = top-left. Dragged corner = bottom-right.
            // In macOS coords: anchor is (minX, maxY) → top-left
            let desiredW = max(minSize, mouse.x - anchorPoint.x)
            let newW = desiredW
            let newH = newW / aspectRatio
            let newX = anchorPoint.x
            let newY = anchorPoint.y - newH  // top-left stays, bottom moves
            applyFrame(NSRect(x: newX, y: newY, width: newW, height: newH), to: win)

        case .resizeBottomLeft:
            // Anchor = top-right
            let desiredW = max(minSize, anchorPoint.x - mouse.x)
            let newW = desiredW
            let newH = newW / aspectRatio
            let newX = anchorPoint.x - newW
            let newY = anchorPoint.y - newH
            applyFrame(NSRect(x: newX, y: newY, width: newW, height: newH), to: win)

        case .resizeTopRight:
            // Anchor = bottom-left
            let desiredW = max(minSize, mouse.x - anchorPoint.x)
            let newW = desiredW
            let newH = newW / aspectRatio
            let newX = anchorPoint.x
            let newY = anchorPoint.y  // bottom stays
            applyFrame(NSRect(x: newX, y: newY, width: newW, height: newH), to: win)

        case .resizeTopLeft:
            // Anchor = bottom-right
            let desiredW = max(minSize, anchorPoint.x - mouse.x)
            let newW = desiredW
            let newH = newW / aspectRatio
            let newX = anchorPoint.x - newW
            let newY = anchorPoint.y  // bottom stays
            applyFrame(NSRect(x: newX, y: newY, width: newW, height: newH), to: win)

        case .none:
            break
        }
    }

    private func applyFrame(_ rect: NSRect, to win: NSWindow) {
        win.setFrame(rect, display: true)
        updateLayout(rect.size)
    }

    override func mouseUp(with event: NSEvent) {
        if isLocked { return }
        guard let win = window else { return }

        // Save position
        NotificationCenter.default.post(name: .desktopPhotoMoved, object: win)

        // If we were resizing, report the new width
        if dragMode != .move && dragMode != .none {
            onResizeFinished?(win.frame.width)
        }
        dragMode = .none
    }

    // MARK: - Right-click menu

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()

        let lockItem = NSMenuItem(
            title: isLocked ? "Unlock Position" : "Lock Position",
            action: #selector(handleLockToggle),
            keyEquivalent: ""
        )
        lockItem.target = self
        menu.addItem(lockItem)

        menu.addItem(.separator())

        let removeItem = NSMenuItem(
            title: "Remove from Desktop",
            action: #selector(handleRemove),
            keyEquivalent: ""
        )
        removeItem.target = self
        menu.addItem(removeItem)

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func handleLockToggle() { onLockToggle?() }
    @objc private func handleRemove() { onRemove?() }

    // MARK: - Lock flash

    func flashLockState(_ locked: Bool) {
        let size: CGFloat = 48
        let indicator = NSView(frame: NSRect(
            x: (bounds.width - size) / 2,
            y: (bounds.height - size) / 2,
            width: size, height: size
        ))
        indicator.wantsLayer = true
        indicator.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
        indicator.layer?.cornerRadius = 12

        let sym = NSImageView(frame: NSRect(x: 8, y: 8, width: 32, height: 32))
        sym.image = NSImage(
            systemSymbolName: locked ? "lock.fill" : "lock.open.fill",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(.init(pointSize: 20, weight: .medium))
        sym.contentTintColor = .white
        indicator.addSubview(sym)
        addSubview(indicator)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                indicator.animator().alphaValue = 0
            } completionHandler: { indicator.removeFromSuperview() }
        }
    }

    // MARK: - Standard overrides

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }
}

// MARK: - Notification

extension Notification.Name {
    static let desktopPhotoMoved = Notification.Name("desktopPhotoMoved")
}
