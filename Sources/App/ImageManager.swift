import AppKit
import SwiftUI
import ServiceManagement

/// Manages multiple desktop photos, persistence, and settings.
@MainActor
class PhotoManager: ObservableObject {
    @Published var photos: [PhotoItem] = []
    @Published var launchAtLogin: Bool = false

    private var windows: [UUID: DesktopPhotoWindow] = [:]

    // v1.4 — Folder watchers and rotation timers
    private var folderWatchers: [UUID: FolderWatcher] = [:]
    private var folderImages: [UUID: [URL]] = [:]
    private var rotationTimers: [UUID: DispatchSourceTimer] = [:]

    var storageDir: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("PhotoWidget", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var dataFile: URL { storageDir.appendingPathComponent("photos.json") }

    init() {
        launchAtLogin = SMAppService.mainApp.status == .enabled

        // Listen for window moves
        NotificationCenter.default.addObserver(
            forName: .desktopPhotoMoved,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? DesktopPhotoWindow,
                  let id = window.photoId else { return }
            Task { @MainActor [weak self] in
                self?.saveWindowPosition(for: id, frame: window.frame)
            }
        }

        // Save on quit
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.saveAllPositions()
                self?.persist()
            }
        }

        // Load saved photos immediately
        loadSaved()
    }

    // MARK: - Persistence

    func loadSaved() {
        guard let data = try? Data(contentsOf: dataFile),
              let items = try? JSONDecoder().decode([PhotoItem].self, from: data) else { return }
        photos = items

        for item in photos where item.isVisible {
            if let folderPath = item.folderPath {
                // Smart Canvas — load from folder
                let folderURL = URL(fileURLWithPath: folderPath)
                let watcher = FolderWatcher(folderURL: folderURL)
                let images = watcher.scanImages()
                folderImages[item.id] = images

                if let imageURL = images[safe: item.folderImageIndex],
                   let image = NSImage(contentsOf: imageURL) {
                    createWindow(for: item, image: image)
                } else if let first = images.first, let image = NSImage(contentsOf: first) {
                    createWindow(for: item, image: image)
                }

                setupFolderWatcher(for: item.id, folderURL: folderURL)
                setupRotationTimer(for: item)
            } else {
                // Single image
                let imageURL = storageDir.appendingPathComponent(item.filename)
                guard let image = NSImage(contentsOf: imageURL) else { continue }
                createWindow(for: item, image: image)
            }
        }
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(photos) else { return }
        try? data.write(to: dataFile, options: .atomic)
    }

    private func saveAllPositions() {
        for (id, window) in windows {
            saveWindowPosition(for: id, frame: window.frame)
        }
    }

    private func saveWindowPosition(for id: UUID, frame: NSRect) {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        photos[index].frameString = NSStringFromRect(frame)
        photos[index].widgetWidth = frame.width

        // Also save per-image config for folder photos if in dynamic mode
        if photos[index].folderPath != nil,
           photos[index].folderSizeMode == "dynamic",
           let images = folderImages[id] {
            let currentImage = images[safe: photos[index].folderImageIndex]
            if let key = currentImage?.lastPathComponent {
                photos[index].folderImageConfigs[key] = FolderImageConfig(
                    frameString: NSStringFromRect(frame),
                    widgetWidth: frame.width
                )
            }
        }

        persist()
    }

    // MARK: - Add / Remove

    func addPhoto(_ image: NSImage) {
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
            return
        }

        let filename = UUID().uuidString + ".jpg"
        try? jpegData.write(to: storageDir.appendingPathComponent(filename))

        let item = PhotoItem(filename: filename)
        photos.append(item)
        createWindow(for: item, image: image)
        persist()
    }

    func addFolder(_ folderURL: URL) {
        let watcher = FolderWatcher(folderURL: folderURL)
        let images = watcher.scanImages()

        // Folder can contain anything — we just filter for images
        if images.isEmpty {
            let alert = NSAlert()
            alert.messageText = "No Images Found"
            alert.informativeText = "The folder \"\(folderURL.lastPathComponent)\" doesn't contain any supported image files (JPEG, PNG, HEIC, TIFF, GIF, WebP, BMP)."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        guard let firstImage = NSImage(contentsOf: images[0]) else { return }

        let folderName = folderURL.lastPathComponent

        var item = PhotoItem(filename: "")
        item.customName = folderName
        item.folderPath = folderURL.path
        item.folderImageIndex = 0
        item.rotationInterval = "click"

        photos.append(item)
        folderImages[item.id] = images

        createWindow(for: item, image: firstImage)
        setupFolderWatcher(for: item.id, folderURL: folderURL)
        persist()
    }

    func removePhoto(_ id: UUID) {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        let item = photos[index]

        windows[id]?.hidePhoto()
        windows.removeValue(forKey: id)

        // Clean up folder watcher
        folderWatchers[id]?.stop()
        folderWatchers.removeValue(forKey: id)
        folderImages.removeValue(forKey: id)
        rotationTimers[id]?.cancel()
        rotationTimers.removeValue(forKey: id)

        // Only delete the file if it's a single-image (not folder) photo
        if item.folderPath == nil {
            try? FileManager.default.removeItem(at: storageDir.appendingPathComponent(item.filename))
        }
        photos.remove(at: index)
        persist()
    }

    func removeAllPhotos() {
        let ids = photos.map { $0.id }
        for id in ids { removePhoto(id) }
    }

    // MARK: - Window Creation

    private func createWindow(for item: PhotoItem, image: NSImage) {
        let window = DesktopPhotoWindow()
        window.isReleasedWhenClosed = false
        window.photoId = item.id
        window.showPhoto(image, baseWidth: item.widgetWidth, locked: item.isLocked, settings: item)

        // Restore saved position
        var targetFrame: NSRect? = nil
        if item.folderSizeMode == "dynamic", item.folderPath != nil, let images = folderImages[item.id] {
            let currentImage = images[safe: item.folderImageIndex]
            if let key = currentImage?.lastPathComponent, let cfg = item.folderImageConfigs[key] {
                targetFrame = NSRectFromString(cfg.frameString)
            }
        }
        
        let fallbackRect = NSRectFromString(item.frameString)
        let rectToUse = targetFrame ?? fallbackRect
        
        if rectToUse.width > 0 { 
            window.setFrame(rectToUse, display: true) 
            (window.contentView as? DraggablePhotoView)?.updateLayout(rectToUse.size)
        }

        // Callbacks
        window.onLockToggle = { [weak self] in self?.toggleLock(item.id) }
        window.onRemove = { [weak self] in self?.removePhoto(item.id) }
        window.onResize = { [weak self] newWidth in
            guard let self, let i = self.photos.firstIndex(where: { $0.id == item.id }) else { return }
            self.photos[i].widgetWidth = newWidth
            self.persist()
        }
        window.onOpacityChanged = { [weak self] newOpacity in
            guard let self, let i = self.photos.firstIndex(where: { $0.id == item.id }) else { return }
            self.photos[i].opacity = newOpacity
            self.persist()
        }

        // Click-to-advance for folder photos
        window.onClickAdvance = { [weak self] in
            guard let self else { return }
            if let idx = self.photos.firstIndex(where: { $0.id == item.id }),
               self.photos[idx].folderPath != nil,
               self.photos[idx].rotationInterval == "click" {
                self.nextFolderImage(item.id)
            }
        }
        // Also wire it on the view
        (window.contentView as? DraggablePhotoView)?.onClickAdvance = window.onClickAdvance

        windows[item.id] = window
    }

    // MARK: - v1.1 Controls

    func setFloating(_ id: UUID, _ floating: Bool) {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        photos[index].isFloating = floating
        windows[id]?.setFloating(floating)
        
        if !floating {
            photos[index].isClickThrough = false
            windows[id]?.setClickThrough(false)
        }
        
        persist()
    }

    func toggleClickThrough(_ id: UUID) {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        photos[index].isClickThrough.toggle()
        windows[id]?.setClickThrough(photos[index].isClickThrough)
        persist()
    }

    func setOpacity(_ id: UUID, _ value: CGFloat) {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        photos[index].opacity = max(0.1, min(1.0, value))
        windows[id]?.setPhotoOpacity(photos[index].opacity)
        persist()
    }

    func toggleLock(_ id: UUID) {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        photos[index].isLocked.toggle()
        let locked = photos[index].isLocked

        windows[id]?.setLocked(locked)
        (windows[id]?.contentView as? DraggablePhotoView)?.flashLockState(locked)
        persist()
    }

    func toggleVisibility(_ id: UUID) {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        photos[index].isVisible.toggle()

        if photos[index].isVisible {
            let item = photos[index]
            if let folderPath = item.folderPath {
                let folderURL = URL(fileURLWithPath: folderPath)
                let images = FolderWatcher(folderURL: folderURL).scanImages()
                folderImages[item.id] = images
                if let imageURL = images[safe: item.folderImageIndex],
                   let image = NSImage(contentsOf: imageURL) {
                    createWindow(for: item, image: image)
                }
                setupFolderWatcher(for: item.id, folderURL: folderURL)
                setupRotationTimer(for: item)
            } else if let image = NSImage(contentsOf: storageDir.appendingPathComponent(item.filename)) {
                createWindow(for: item, image: image)
            }
        } else {
            windows[id]?.hidePhoto()
            windows.removeValue(forKey: id)
            folderWatchers[id]?.stop()
            folderWatchers.removeValue(forKey: id)
            rotationTimers[id]?.cancel()
            rotationTimers.removeValue(forKey: id)
        }
        persist()
    }

    func resize(_ id: UUID, to width: CGFloat) {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        photos[index].widgetWidth = width
        windows[id]?.resizeTo(width: width)
        persist()
    }

    // MARK: - v1.2 Naming & Organization

    func renamePhoto(_ id: UUID, to name: String) {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        photos[index].customName = name.isEmpty ? nil : name
        persist()
    }

    func replacePhoto(_ id: UUID, with newImage: NSImage) {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        let item = photos[index]

        // Only replace file for single-image photos
        if item.folderPath == nil {
            guard let tiffData = newImage.tiffRepresentation,
                  let bitmapRep = NSBitmapImageRep(data: tiffData),
                  let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else { return }
            try? jpegData.write(to: storageDir.appendingPathComponent(item.filename))
        }

        // Refresh window with crossfade
        windows[id]?.swapImage(newImage, animate: true)
        persist()
    }

    func duplicatePhoto(_ id: UUID) {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        let original = photos[index]

        if original.folderPath != nil {
            // Duplicate folder photo — just copy the settings
            var newItem = PhotoItem(filename: "")
            newItem.customName = (original.customName ?? "Photo") + " (Copy)"
            newItem.folderPath = original.folderPath
            newItem.rotationInterval = original.rotationInterval
            newItem.folderImageIndex = original.folderImageIndex
            newItem.widgetWidth = original.widgetWidth
            copyAppearanceSettings(from: original, to: &newItem)

            // Offset position
            if !original.frameString.isEmpty {
                var rect = NSRectFromString(original.frameString)
                rect.origin.x += 30
                rect.origin.y -= 30
                newItem.frameString = NSStringFromRect(rect)
            }

            photos.append(newItem)

            if let images = folderImages[original.id],
               let imageURL = images[safe: newItem.folderImageIndex],
               let image = NSImage(contentsOf: imageURL) {
                folderImages[newItem.id] = images
                createWindow(for: newItem, image: image)
                if let folderPath = newItem.folderPath {
                    setupFolderWatcher(for: newItem.id, folderURL: URL(fileURLWithPath: folderPath))
                    setupRotationTimer(for: newItem)
                }
            }
        } else {
            // Copy the file
            let newFilename = UUID().uuidString + ".jpg"
            let srcURL = storageDir.appendingPathComponent(original.filename)
            let dstURL = storageDir.appendingPathComponent(newFilename)
            try? FileManager.default.copyItem(at: srcURL, to: dstURL)

            var newItem = PhotoItem(filename: newFilename, width: original.widgetWidth)
            newItem.customName = (original.customName ?? "Photo") + " (Copy)"
            copyAppearanceSettings(from: original, to: &newItem)

            // Offset position
            if !original.frameString.isEmpty {
                var rect = NSRectFromString(original.frameString)
                rect.origin.x += 30
                rect.origin.y -= 30
                newItem.frameString = NSStringFromRect(rect)
            }

            photos.append(newItem)

            if let image = NSImage(contentsOf: dstURL) {
                createWindow(for: newItem, image: image)
            }
        }

        persist()
    }

    func movePhoto(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              sourceIndex >= 0, sourceIndex < photos.count,
              destinationIndex >= 0, destinationIndex < photos.count else { return }
        let item = photos.remove(at: sourceIndex)
        photos.insert(item, at: destinationIndex)
        persist()
    }

    private func copyAppearanceSettings(from src: PhotoItem, to dst: inout PhotoItem) {
        dst.isFloating = src.isFloating
        dst.isClickThrough = src.isClickThrough
        dst.opacity = src.opacity
        dst.cornerRadius = src.cornerRadius
        dst.shadowEnabled = src.shadowEnabled
        dst.shadowBlur = src.shadowBlur
        dst.shadowOpacity = src.shadowOpacity
        dst.borderWidth = src.borderWidth
        dst.borderColorHex = src.borderColorHex
        dst.vignetteEnabled = src.vignetteEnabled
    }

    // MARK: - v1.3 Aesthetic Controls

    func setCornerRadius(_ id: UUID, _ value: CGFloat) {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        photos[index].cornerRadius = value
        (windows[id]?.contentView as? DraggablePhotoView)?.setCornerRadius(value)
        persist()
    }

    func setShadow(_ id: UUID, enabled: Bool, blur: CGFloat, opacity: CGFloat) {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        photos[index].shadowEnabled = enabled
        photos[index].shadowBlur = blur
        photos[index].shadowOpacity = opacity
        windows[id]?.applyShadowSettings(enabled: enabled, blur: blur, opacity: opacity)
        persist()
    }

    func setBorder(_ id: UUID, width: CGFloat, colorHex: String) {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        photos[index].borderWidth = width
        photos[index].borderColorHex = colorHex
        let color = NSColor.fromHex(colorHex) ?? .white
        (windows[id]?.contentView as? DraggablePhotoView)?.applyBorder(width: width, color: color)
        persist()
    }

    func setVignette(_ id: UUID, enabled: Bool) {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        photos[index].vignetteEnabled = enabled
        if enabled {
            (windows[id]?.contentView as? DraggablePhotoView)?.applyVignette()
        } else {
            (windows[id]?.contentView as? DraggablePhotoView)?.removeVignette()
        }
        persist()
    }

    // MARK: - v1.4 Smart Canvas

    func setFolder(_ id: UUID, folderURL: URL) {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        photos[index].folderPath = folderURL.path
        photos[index].folderImageIndex = 0
        photos[index].customName = photos[index].customName ?? folderURL.lastPathComponent

        let watcher = FolderWatcher(folderURL: folderURL)
        let images = watcher.scanImages()
        folderImages[id] = images

        if let firstURL = images.first, let image = NSImage(contentsOf: firstURL) {
            windows[id]?.swapImage(image, animate: true)
        }

        setupFolderWatcher(for: id, folderURL: folderURL)
        setupRotationTimer(for: photos[index])
        persist()
    }

    func removeFolder(_ id: UUID) {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        photos[index].folderPath = nil
        photos[index].folderImageIndex = 0
        folderWatchers[id]?.stop()
        folderWatchers.removeValue(forKey: id)
        folderImages.removeValue(forKey: id)
        rotationTimers[id]?.cancel()
        rotationTimers.removeValue(forKey: id)
        persist()
    }

    func nextFolderImage(_ id: UUID) {
        guard let index = photos.firstIndex(where: { $0.id == id }),
              photos[index].isVisible,
              let images = folderImages[id], !images.isEmpty else { return }

        let item = photos[index]

        if item.folderSizeMode == "dynamic" {
            saveFolderImageConfig(for: id)
        }

        // Advance
        photos[index].folderImageIndex = (photos[index].folderImageIndex + 1) % images.count
        let imageURL = images[photos[index].folderImageIndex]

        if let image = NSImage(contentsOf: imageURL) {
            let key = imageURL.lastPathComponent
            let targetFrame = item.folderImageConfigs[key].map { NSRectFromString($0.frameString) }
            windows[id]?.swapImage(image, targetFrame: targetFrame, mode: item.folderSizeMode, animate: true)
        }
        persist()
    }

    func prevFolderImage(_ id: UUID) {
        guard let index = photos.firstIndex(where: { $0.id == id }),
              let images = folderImages[id], !images.isEmpty else { return }

        let item = photos[index]

        if item.folderSizeMode == "dynamic" {
            saveFolderImageConfig(for: id)
        }

        // Go back
        let currentIndex = photos[index].folderImageIndex
        photos[index].folderImageIndex = currentIndex > 0 ? currentIndex - 1 : images.count - 1
        let imageURL = images[photos[index].folderImageIndex]

        if let image = NSImage(contentsOf: imageURL) {
            let key = imageURL.lastPathComponent
            let targetFrame = item.folderImageConfigs[key].map { NSRectFromString($0.frameString) }
            windows[id]?.swapImage(image, targetFrame: targetFrame, mode: item.folderSizeMode, animate: true)
        }
        persist()
    }

    func setRotationInterval(_ id: UUID, _ interval: String) {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        photos[index].rotationInterval = interval
        rotationTimers[id]?.cancel()
        rotationTimers.removeValue(forKey: id)
        setupRotationTimer(for: photos[index])
        persist()
    }

    func setCustomRotationSeconds(_ id: UUID, _ seconds: Int) {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        photos[index].customRotationSeconds = max(5, seconds)  // minimum 5 seconds
        // Restart timer if currently on custom
        if photos[index].rotationInterval == "custom" {
            rotationTimers[id]?.cancel()
            rotationTimers.removeValue(forKey: id)
            setupRotationTimer(for: photos[index])
        }
        persist()
    }

    func setFolderSizeMode(_ id: UUID, _ mode: String) {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        let oldMode = photos[index].folderSizeMode
        photos[index].folderSizeMode = mode

        if oldMode == "dynamic" && mode == "fixed" {
            // We just switched to fixed. Update the frameString to current frame so all images use it.
            if let window = windows[id] {
                photos[index].frameString = NSStringFromRect(window.frame)
                photos[index].widgetWidth = window.frame.width
            }
        }

        // Trigger an immediate swap so the window resizes or adapts to the new mode
        if let images = folderImages[id], !images.isEmpty {
            let imageURL = images[photos[index].folderImageIndex]
            if let image = NSImage(contentsOf: imageURL) {
                let key = imageURL.lastPathComponent
                let targetFrame = photos[index].folderImageConfigs[key].map { NSRectFromString($0.frameString) }
                windows[id]?.swapImage(image, targetFrame: targetFrame, mode: mode, animate: true)
            }
        }
        persist()
    }

    func folderImageCount(_ id: UUID) -> Int {
        folderImages[id]?.count ?? 0
    }

    private func setupFolderWatcher(for id: UUID, folderURL: URL) {
        folderWatchers[id]?.stop()
        let watcher = FolderWatcher(folderURL: folderURL)
        watcher.onChange = { [weak self] urls in
            guard let self else { return }
            Task { @MainActor in
                self.folderImages[id] = urls
            }
        }
        watcher.start()
        folderWatchers[id] = watcher
    }

    private func setupRotationTimer(for item: PhotoItem) {
        let interval: TimeInterval?
        switch item.rotationInterval {
        case "30s":    interval = 30
        case "5m":     interval = 300
        case "hourly": interval = 3600
        case "daily":  interval = 86400
        case "custom": interval = TimeInterval(max(5, item.customRotationSeconds))
        default:       interval = nil   // "click" doesn't use timers
        }

        guard let seconds = interval else { return }

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + seconds, repeating: seconds)
        timer.setEventHandler { [weak self] in
            self?.nextFolderImage(item.id)
        }
        timer.resume()
        rotationTimers[item.id] = timer
    }

    /// Save the current window position/size for the currently displayed folder image.
    private func saveFolderImageConfig(for id: UUID) {
        guard let index = photos.firstIndex(where: { $0.id == id }),
              let images = folderImages[id],
              let window = windows[id] else { return }
        let currentImage = images[safe: photos[index].folderImageIndex]
        if let key = currentImage?.lastPathComponent {
            photos[index].folderImageConfigs[key] = FolderImageConfig(
                frameString: NSStringFromRect(window.frame),
                widgetWidth: window.frame.width
            )
        }
    }

    // MARK: - App Controls

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchAtLogin = enabled
        } catch {
            print("Launch at login error: \(error)")
        }
    }

    /// Returns a small thumbnail for UI display.
    func thumbnail(for item: PhotoItem, size: CGFloat = 48) -> NSImage? {
        let image: NSImage?
        if let folderPath = item.folderPath {
            let folderURL = URL(fileURLWithPath: folderPath)
            let images = folderImages[item.id] ?? FolderWatcher(folderURL: folderURL).scanImages()
            if let imageURL = images[safe: item.folderImageIndex] {
                image = NSImage(contentsOf: imageURL)
            } else {
                image = images.first.flatMap { NSImage(contentsOf: $0) }
            }
        } else {
            let url = storageDir.appendingPathComponent(item.filename)
            image = NSImage(contentsOf: url)
        }

        guard let sourceImage = image else { return nil }

        let thumb = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let ar = sourceImage.size.width / sourceImage.size.height
            let drawRect: NSRect
            if ar > 1 {
                let h = size / ar
                drawRect = NSRect(x: 0, y: (size - h) / 2, width: size, height: h)
            } else {
                let w = size * ar
                drawRect = NSRect(x: (size - w) / 2, y: 0, width: w, height: size)
            }
            sourceImage.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            return true
        }
        return thumb
    }

    /// Label for a photo.
    func label(for item: PhotoItem) -> String {
        if let name = item.customName, !name.isEmpty {
            return name
        }
        guard let index = photos.firstIndex(where: { $0.id == item.id }) else { return "Photo" }
        return "Photo \(index + 1)"
    }
}

// MARK: - Safe Array Access

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
