import AppKit
import SwiftUI

/// AppDelegate manages the menu bar status item and the settings window.
/// This gives us full control to hide/show the menu bar icon.
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var settingsWindow: NSWindow?
    let manager = PhotoManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()

        // If first launch (no photos yet), show settings
        if manager.photos.isEmpty {
            showSettingsWindow()
        }
    }

    /// When user re-opens the app (clicks .app again while running), show UI
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showStatusItem()
        showSettingsWindow()
        return false
    }

    // MARK: - Status Item (Menu Bar Icon)

    func setupStatusItem() {
        guard UserDefaults.standard.object(forKey: "hideMenuBarIcon") == nil ||
              !UserDefaults.standard.bool(forKey: "hideMenuBarIcon") else {
            return  // User chose to hide it
        }
        showStatusItem()
    }

    func showStatusItem() {
        if statusItem != nil { return }  // already showing

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "photo.on.rectangle", accessibilityDescription: "Photo Widget OSX")
        statusItem?.button?.toolTip = "Photo Widget OSX"
        statusItem?.button?.image?.size = NSSize(width: 18, height: 18)

        UserDefaults.standard.set(false, forKey: "hideMenuBarIcon")
        rebuildMenu()
    }

    func hideStatusItem() {
        statusItem?.statusBar?.removeStatusItem(statusItem!)
        statusItem = nil
        UserDefaults.standard.set(true, forKey: "hideMenuBarIcon")
    }

    func rebuildMenu() {
        let menu = NSMenu()

        // Add Photo
        let addItem = NSMenuItem(title: "Add Photo…", action: #selector(addPhoto), keyEquivalent: "")
        addItem.target = self
        menu.addItem(addItem)

        // Open Settings
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettingsFromMenu), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        if !manager.photos.isEmpty {
            menu.addItem(.separator())

            // Per-photo submenus with thumbnails
            for (index, item) in manager.photos.enumerated() {
                let submenu = NSMenu()

                let visItem = NSMenuItem(
                    title: item.isVisible ? "Hide" : "Show",
                    action: #selector(togglePhotoVisibility(_:)),
                    keyEquivalent: ""
                )
                visItem.target = self
                visItem.tag = index
                submenu.addItem(visItem)

                let lockItem = NSMenuItem(
                    title: item.isLocked ? "Unlock Position" : "Lock Position",
                    action: #selector(togglePhotoLock(_:)),
                    keyEquivalent: ""
                )
                lockItem.target = self
                lockItem.tag = index
                submenu.addItem(lockItem)

                submenu.addItem(.separator())

                let removeItem = NSMenuItem(
                    title: "Remove",
                    action: #selector(removePhotoMenu(_:)),
                    keyEquivalent: ""
                )
                removeItem.target = self
                removeItem.tag = index
                submenu.addItem(removeItem)

                // Photo menu item with thumbnail
                let photoItem = NSMenuItem()
                photoItem.submenu = submenu

                // Create attributed title with thumbnail
                let title = "Photo \(index + 1)"
                if let thumb = manager.thumbnail(for: item, size: 20) {
                    photoItem.image = thumb
                    photoItem.image?.size = NSSize(width: 20, height: 20)
                }
                photoItem.title = title

                // Status indicators
                var status = ""
                if !item.isVisible { status += " — hidden" }
                if item.isLocked { status += " — locked" }
                if !status.isEmpty { photoItem.title = title + status } else { photoItem.title = title }

                menu.addItem(photoItem)
            }

            menu.addItem(.separator())

            let removeAllItem = NSMenuItem(title: "Remove All Photos", action: #selector(removeAllPhotos), keyEquivalent: "")
            removeAllItem.target = self
            menu.addItem(removeAllItem)
        }

        menu.addItem(.separator())

        // Launch at Login
        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = manager.launchAtLogin ? .on : .off
        menu.addItem(loginItem)

        // Hide Menu Bar Icon
        let hideItem = NSMenuItem(title: "Hide Menu Bar Icon", action: #selector(hideMenuBarIcon), keyEquivalent: "")
        hideItem.target = self
        menu.addItem(hideItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Photo Widget", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    // MARK: - Settings Window

    @objc func showSettingsFromMenu() {
        showSettingsWindow()
    }

    func showSettingsWindow() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = ContentView(manager: manager, onMenuUpdate: { [weak self] in
            self?.rebuildMenu()
        })

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 500),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Photo Widget OSX"
        window.center()
        window.contentView = NSHostingView(rootView: contentView)
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    // MARK: - Menu Actions

    @objc func addPhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .png, .jpeg, .heic, .tiff]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Add"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK {
            for url in panel.urls {
                if let img = NSImage(contentsOf: url) {
                    manager.addPhoto(img)
                }
            }
            rebuildMenu()
        }
    }

    @objc func togglePhotoVisibility(_ sender: NSMenuItem) {
        let index = sender.tag
        guard index < manager.photos.count else { return }
        manager.toggleVisibility(manager.photos[index].id)
        rebuildMenu()
    }

    @objc func togglePhotoLock(_ sender: NSMenuItem) {
        let index = sender.tag
        guard index < manager.photos.count else { return }
        manager.toggleLock(manager.photos[index].id)
        rebuildMenu()
    }

    @objc func removePhotoMenu(_ sender: NSMenuItem) {
        let index = sender.tag
        guard index < manager.photos.count else { return }
        manager.removePhoto(manager.photos[index].id)
        rebuildMenu()
    }

    @objc func removeAllPhotos() {
        manager.removeAllPhotos()
        rebuildMenu()
    }

    @objc func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let newState = sender.state == .off
        manager.setLaunchAtLogin(newState)
        rebuildMenu()
    }

    @objc func hideMenuBarIcon() {
        hideStatusItem()
        // Show a brief alert so user knows how to get it back
        let alert = NSAlert()
        alert.messageText = "Menu Bar Icon Hidden"
        alert.informativeText = "To bring it back, just open Photo Widget again from your Applications folder or Spotlight."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }
}
