# Releasing Photo Widget OSX

Step-by-step guide to build the DMG, publish a GitHub Release, and set up the Homebrew Cask.

---

## Part 1 — Build the DMG in Xcode

### Step 1: Archive the app

1. In Xcode, make sure the scheme is **PhotoWidgetOSX** and destination is **Any Mac**.
2. Menu → **Product → Archive**
3. Xcode Organizer opens. Wait for it to finish.

### Step 2: Export the app

1. In Organizer, select the archive → click **Distribute App**
2. Choose **Direct Distribution** (not App Store)
3. Choose **Export** (not notarize — we're skipping that for now)
4. Uncheck "Upload to App Store Connect"
5. Choose a location, e.g. `~/Desktop/PhotoWidgetOSX-export/`
6. Click **Export**

This gives you `Photo Widget OSX.app`.

### Step 3: Create the DMG

Open Terminal and run:

```bash
# Create a temporary disk image folder
mkdir -p ~/Desktop/dmg-staging
cp -R ~/Desktop/PhotoWidgetOSX-export/"Photo Widget OSX.app" ~/Desktop/dmg-staging/

# Add a symlink to /Applications for drag-install
ln -s /Applications ~/Desktop/dmg-staging/Applications

# Create the DMG
hdiutil create \
  -volname "Photo Widget OSX" \
  -srcfolder ~/Desktop/dmg-staging \
  -ov \
  -format UDZO \
  ~/Desktop/"Photo Widget OSX-1.0.0.dmg"

# Clean up staging
rm -rf ~/Desktop/dmg-staging
```

Your DMG is now at `~/Desktop/Photo Widget OSX-1.0.0.dmg`.

---

## Part 2 — GitHub Release

### Step 1: Set up your repo

```bash
cd "/Users/yashashwisinghania/Photo WidgetOSX"
git init
git add .
git commit -m "v1.0.0 — initial release"
git branch -M main
git remote add origin git@github.com:yashashwi-s/PhotoWidgetOSX.git
git push -u origin main
```

### Step 2: Tag the release

```bash
git tag v1.0.0
git push origin v1.0.0
```

### Step 3: Upload the DMG to GitHub

1. Go to `github.com/yashashwi-s/PhotoWidgetOSX/releases/new`
2. Tag: `v1.0.0`
3. Title: `Photo Widget OSX 1.0.0`
4. Description:
   ```
   ## What's new in v1.0.0
   - Initial release
   - Place any photo on your desktop with perfect aspect ratio
   - Drag to move, drag corners to resize
   - Right-click to lock/remove
   - Persistent across restarts
   - Launch at Login support
   ```
5. Attach the DMG file
6. Click **Publish release**

### Step 4: Get the SHA256 of your DMG (needed for Homebrew)

```bash
shasum -a 256 ~/Desktop/"Photo Widget OSX-1.0.0.dmg"
```

Copy this hash — you'll need it for the Cask formula.

---

## Part 3 — Homebrew Cask

### Step 1: Create a Homebrew Tap repo

1. Create a new GitHub repo named `homebrew-tap`
   - URL will be: `github.com/yashashwi-s/homebrew-tap`
2. Clone it locally:
   ```bash
   git clone git@github.com:yashashwi-s/homebrew-tap.git
   cd homebrew-tap
   mkdir Casks
   ```

### Step 2: Write the Cask formula

Create `Casks/photo-widget-osx.rb`:

```ruby
cask "photo-widget-osx" do
  version "1.0.0"
  sha256 "PASTE_YOUR_SHA256_HERE"

  url "https://github.com/yashashwi-s/PhotoWidgetOSX/releases/download/v#{version}/Photo.Widget.OSX-#{version}.dmg"

  name "Photo Widget OSX"
  desc "Place any photo on your macOS desktop with perfect aspect ratio"
  homepage "https://github.com/yashashwi-s/PhotoWidgetOSX"

  app "Photo Widget OSX.app"

  zap trash: [
    "~/Library/Application Support/PhotoWidget",
    "~/Library/Preferences/com.yashashwi.photowidgetosx.plist",
  ]
end
```

> **Note on the DMG filename:** Name it without spaces when uploading: `Photo.Widget.OSX-1.0.0.dmg`. Update the URL in the formula accordingly.

### Step 3: Push and test the Cask

```bash
# Commit the formula
git add Casks/photo-widget-osx.rb
git commit -m "Add photo-widget-osx cask v1.0.0"
git push

# Test installation locally first
brew install --cask --no-quarantine "yashashwi-s/tap/photo-widget-osx"

# If it works, users install with:
brew tap yashashwi-s/tap
brew install --cask photo-widget-osx
```

---

## Part 4 — Gatekeeper Note for Users

Since the app isn't notarized (requires $99/yr Apple Developer account), users will see a security warning. Add these instructions to your download page:

```
First time opening Photo Widget OSX:
1. Don't double-click — right-click the app instead
2. Choose "Open" from the menu
3. Click "Open" in the dialog that appears
4. Done — you won't be asked again
```

Or they can run:
```bash
xattr -dr com.apple.quarantine "/Applications/Photo Widget OSX.app"
```

---

## Checklist

- [ ] Archive built in Xcode (Release scheme)
- [ ] DMG created with Applications symlink
- [ ] DMG renamed without spaces: `Photo.Widget.OSX-1.0.0.dmg`
- [ ] Git repo initialised and pushed to GitHub
- [ ] v1.0.0 tag pushed
- [ ] DMG uploaded to GitHub Releases
- [ ] SHA256 hash copied
- [ ] `homebrew-tap` repo created
- [ ] Cask formula written with correct URL and SHA256
- [ ] Cask tested locally
- [ ] README download links updated with real GitHub URL
