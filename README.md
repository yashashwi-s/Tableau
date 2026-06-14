# Photo Widget OSX

> Place any photo on your macOS desktop as a perfectly fitted, borderless widget — exactly the right aspect ratio, no cropping, no black bars.

<br>
<p align="center">
  <img src="assets/demo.gif" alt="Photo Widget OSX Action Demo" width="100%" />
</p>
<br>
![macOS](https://img.shields.io/badge/macOS-14.0+-black?style=flat-square&logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.9-orange?style=flat-square&logo=swift)
![License](https://img.shields.io/badge/License-MIT-blue?style=flat-square)
![Version](https://img.shields.io/badge/Version-1.0.0-green?style=flat-square)

## What is this?

Photo Widget OSX is a lightweight macOS menu bar app that places photos directly on your desktop as **borderless, always-on-desktop overlays** that perfectly match each image's native aspect ratio.

Unlike Apple's built-in WidgetKit widgets (which lock you to 4 fixed sizes and crop your images), Photo Widget OSX creates a custom-sized window for each photo — so a 16:9 landscape stays 16:9, a 3:4 portrait stays 3:4, and a panorama stays a panorama.

## Download

**[⬇️ Download latest release](https://github.com/yashashwi-s/PhotoWidgetOSX/releases/latest)**

Or install via Homebrew:
```bash
brew tap yashashwi-s/tap
brew trust yashashwi-s/tap
brew install --cask photo-widget-osx
```

> **Note:** Since this app is not notarized (no $99 Apple Developer account required!), macOS will show a security warning on first launch. To open it: **right-click the app → Open → Open**.

## Quick Start

1. Download and open `Photo Widget OSX.dmg`
2. Drag the app to your Applications folder
3. Launch it — a 📷 icon appears in your **menu bar**
4. Click **Add Photo…** to pick images from your Mac
5. Your photos appear on your desktop — **drag them anywhere**
6. **Right-click** any photo to lock its position or remove it
7. **Drag corners** to resize (aspect ratio is always maintained)

## Features

- 🖼️ **Any aspect ratio** — no cropping, no black bars, ever
- 📌 **Multiple photos** — add as many as you want, each independent
- 🔒 **Lock position** — right-click photo or use menu bar to lock/unlock
- ↔️ **Corner resize** — drag any corner to resize (aspect ratio locked)
- 🚀 **Launch at Login** — starts automatically with your Mac
- 💾 **Remembers everything** — photos, positions, sizes, lock states all persist
- 🔽 **Hide menu bar icon** — use menu → reopen app from Spotlight to show it again
- 🪶 **Ultra lightweight** — ~20MB RAM, zero CPU when idle
- 🎨 **Rounded corners + shadow** — native macOS widget aesthetic

## Why not the App Store?

Apple's WidgetKit (what powers desktop widgets) only supports 4 fixed sizes. Photo Widget OSX bypasses this entirely using borderless desktop windows — which Apple's sandboxing rules don't allow on the App Store. So we're free and open source instead.

## Competitive Landscape

| App | Custom Ratio | Free | Method |
|-----|:---:|:---:|--------|
| **Photo Widget OSX** | ✅ Any ratio | ✅ Free & OSS | Desktop overlay |
| Apple Photos Widget | ❌ 4 fixed sizes | ✅ Built-in | WidgetKit |
| WidgetWall | ❌ Fixed sizes | Freemium | WidgetKit |
| Color Widgets | ❌ Fixed sizes | Freemium ~$5 | WidgetKit |
| Superlayer | ⚠️ Limited | 💰 Paid sub | Desktop overlay |

## System Requirements

- macOS 14.0 Sonoma or later
- Apple Silicon or Intel Mac

## Building from Source

```bash
# Install XcodeGen
brew install xcodegen

# Clone the repo
git clone https://github.com/yashashwi-s/PhotoWidgetOSX.git
cd PhotoWidgetOSX

# Generate Xcode project
xcodegen generate

# Open in Xcode and hit ⌘R
open PhotoWidgetOSX.xcodeproj
```

## License

MIT — use it, fork it, do whatever you want.

## Roadmap

See [FEATURES.md](FEATURES.md) for what's coming next.
