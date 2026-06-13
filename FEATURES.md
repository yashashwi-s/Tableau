# Photo Widget OSX — Features

## ✅ Implemented (v1.0.0)

### Core
- [x] Desktop photo overlay — borderless NSWindow at desktop level, behind all normal windows
- [x] Exact aspect ratio matching — window sized precisely from the image's native dimensions
- [x] Multiple photos — add as many as you want, each with their own independent window
- [x] Rounded corners — 16px continuous corners, scales down proportionally for smaller sizes
- [x] Drop shadow — subtle shadow for depth, matching native macOS widget aesthetic

### Interaction
- [x] Drag to reposition — click and drag anywhere on the photo to move it
- [x] Lock position — right-click or menu bar to lock (prevents accidental moves)
- [x] Resize from corners — drag any corner; aspect ratio is always maintained
- [x] Cursor feedback — cursor changes to crosshair near corners, open hand in center

### Persistence
- [x] Remember photos — JPEG copies stored in Application Support/PhotoWidget/
- [x] Remember position — window frame (x, y) persisted per photo
- [x] Remember size — widget width persisted per photo
- [x] Remember lock state — per photo
- [x] Remember visibility — per photo
- [x] Persist on quit — saves everything when app quits (NSApplication.willTerminate)
- [x] Restore on launch — all photos and positions reload from disk on startup

### App
- [x] Menu bar agent — LSUIElement, no dock icon
- [x] NSStatusItem menu — full control: add, show/hide, lock/unlock, remove, quit
- [x] Per-photo submenus with thumbnail images in menu
- [x] Lock/remove via right-click directly on the photo
- [x] Settings window — photo list with visibility/remove controls + launch at login
- [x] Hide menu bar icon — reopen app to show it again
- [x] Launch at Login — SMAppService
- [x] Multi-select file picker — add multiple photos at once

### Design
- [x] App icon — custom blue-purple gradient with photo frame
- [x] Clean lock state: "· Locked" text label (no emojis)
- [x] Status text in menu: "Photo 1 — locked", "Photo 2 — hidden"

### Performance
- [x] Ultra lightweight — ~20MB RAM, zero CPU at idle
- [x] JPEG at 90% quality — good balance of size and quality
- [x] No background timers or polling

---

## 🔮 Roadmap

### v1.1 — Polish
- [ ] Right-click show context menu position indicator ("click to dismiss")
- [ ] Snap to screen edges when dragging near a border
- [ ] Keyboard shortcut to show/hide all photos (⌘H in settings)
- [ ] Multi-display awareness — remember which screen each photo was on
- [ ] Smoother resize animation (no flicker on fast drag)

### v1.2 — Customisation
- [ ] Custom corner radius per photo (0 = square, max = fully rounded)
- [ ] Photo opacity/transparency slider per photo
- [ ] Thin border option with colour picker
- [ ] Shadow intensity control

### v1.3 — Grid & Layout
- [ ] Custom grid — define rows/columns, photos snap into a layout
- [ ] Collage mode — auto-arrange multiple photos in a collage
- [ ] Group photos — move/resize multiple photos together as a unit
- [ ] Smart alignment guides when dragging near other photos

### v1.4 — Content
- [ ] Slideshow mode — rotate photos in a window on a configurable timer
- [ ] Folder watching — point to a folder, auto-update when photos change
- [ ] Photos.app integration — pick directly from your Photos library
- [ ] Animated GIF support

### v1.5 — Distribution
- [ ] Homebrew Cask — `brew install --cask photo-widget-osx`
- [ ] GitHub Actions CI — auto-build DMG on each tagged release
- [ ] Auto-update — check GitHub Releases for new versions

---

## Architecture

```
Sources/App/
├── PhotoWidgetOSXApp.swift   # App entry — @NSApplicationDelegateAdaptor
├── AppDelegate.swift         # NSStatusItem + settings window management
├── ContentView.swift         # SwiftUI settings UI
├── DesktopPhotoWindow.swift  # Borderless NSWindow + drag/resize/right-click
├── PhotoItem.swift           # Codable data model per photo
├── ImageManager.swift        # PhotoManager — orchestrates all photos + persistence
└── Assets.xcassets/
    └── AppIcon.appiconset/   # Icon at all required sizes (16–1024px)
```

**Storage:**
```
~/Library/Application Support/PhotoWidget/
├── photos.json               # All PhotoItem state (Codable, atomic write)
└── *.jpg                     # Copies of each added photo at 90% JPEG quality
```
