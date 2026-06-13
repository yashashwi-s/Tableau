import AppKit
import SwiftUI
import ServiceManagement

/// Manages multiple desktop photos, persistence, and settings.
@MainActor
class PhotoManager: ObservableObject {
    @Published var photos: [PhotoItem] = []
    @Published var launchAtLogin: Bool = false

    private var windows: [UUID: DesktopPhotoWindow] = [:]

    private var storageDir: URL {
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
            let imageURL = storageDir.appendingPathComponent(item.filename)
            guard let image = NSImage(contentsOf: imageURL) else { continue }
            createWindow(for: item, image: image)
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
        persist()
    }

    // MARK: - Add / Remove

    func addPhoto(_ image: NSImage) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        guard let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else { return }

        let filename = UUID().uuidString + ".jpg"
        try? jpegData.write(to: storageDir.appendingPathComponent(filename))

        let item = PhotoItem(filename: filename)
        photos.append(item)
        createWindow(for: item, image: image)
        persist()
    }

    func removePhoto(_ id: UUID) {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        let item = photos[index]

        windows[id]?.hidePhoto()
        windows.removeValue(forKey: id)

        try? FileManager.default.removeItem(at: storageDir.appendingPathComponent(item.filename))
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
        window.photoId = item.id
        window.showPhoto(image, baseWidth: item.widgetWidth, locked: item.isLocked)

        // Restore saved position
        if !item.frameString.isEmpty {
            let rect = NSRectFromString(item.frameString)
            if rect.width > 0 { window.setFrameOrigin(rect.origin) }
        }

        // Callbacks
        window.onLockToggle = { [weak self] in self?.toggleLock(item.id) }
        window.onRemove = { [weak self] in self?.removePhoto(item.id) }
        window.onResize = { [weak self] newWidth in
            guard let self, let i = self.photos.firstIndex(where: { $0.id == item.id }) else { return }
            self.photos[i].widgetWidth = newWidth
            self.persist()
        }

        windows[item.id] = window
    }

    // MARK: - Controls

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
            if let image = NSImage(contentsOf: storageDir.appendingPathComponent(item.filename)) {
                createWindow(for: item, image: image)
            }
        } else {
            windows[id]?.hidePhoto()
            windows.removeValue(forKey: id)
        }
        persist()
    }

    func resize(_ id: UUID, to width: CGFloat) {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        photos[index].widgetWidth = width
        windows[id]?.resizeTo(width: width)
        persist()
    }

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
        let url = storageDir.appendingPathComponent(item.filename)
        guard let image = NSImage(contentsOf: url) else { return nil }

        let thumb = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let ar = image.size.width / image.size.height
            let drawRect: NSRect
            if ar > 1 {
                let h = size / ar
                drawRect = NSRect(x: 0, y: (size - h) / 2, width: size, height: h)
            } else {
                let w = size * ar
                drawRect = NSRect(x: (size - w) / 2, y: 0, width: w, height: size)
            }
            image.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            return true
        }
        return thumb
    }

    /// Label for a photo.
    func label(for item: PhotoItem) -> String {
        guard let index = photos.firstIndex(where: { $0.id == item.id }) else { return "Photo" }
        return "Photo \(index + 1)"
    }
}

