import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var manager: PhotoManager
    var onMenuUpdate: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Photo Widget OSX")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Spacer()
                Button {
                    pickFile()
                } label: {
                    Label("Add Photo", systemImage: "plus")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(16)

            Divider()

            if manager.photos.isEmpty {
                emptyView
            } else {
                photoList
            }

            Divider()

            // Footer
            HStack(spacing: 12) {
                Toggle("Launch at Login", isOn: Binding(
                    get: { manager.launchAtLogin },
                    set: {
                        manager.setLaunchAtLogin($0)
                        onMenuUpdate?()
                    }
                ))
                .toggleStyle(.checkbox)
                .font(.system(size: 11))

                Spacer()

                Text("Right-click photo for options")
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 36, weight: .ultraLight))
                .foregroundStyle(.tertiary)
            Text("Add photos to place them\non your desktop.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Choose Photo…") { pickFile() }
                .buttonStyle(.bordered)
            Spacer()
        }
    }

    // MARK: - Photo List

    private var photoList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(manager.photos) { item in
                    photoRow(item)
                }
            }
            .padding(12)
        }
    }

    private func photoRow(_ item: PhotoItem) -> some View {
        HStack(spacing: 10) {
            // Thumbnail
            if let thumb = manager.thumbnail(for: item) {
                Image(nsImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.quaternary)
                    .frame(width: 44, height: 44)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(item.isVisible ? "On desktop" : "Hidden")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(item.isVisible ? .primary : .secondary)
                    if item.isLocked {
                        Text("· Locked")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                    }
                }
                Text("Drag corners to resize · Right-click for options")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // Actions
            HStack(spacing: 4) {
                Button {
                    manager.toggleVisibility(item.id)
                    onMenuUpdate?()
                } label: {
                    Image(systemName: item.isVisible ? "eye" : "eye.slash")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .help(item.isVisible ? "Hide" : "Show")

                Button(role: .destructive) {
                    manager.removePhoto(item.id)
                    onMenuUpdate?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Remove")
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.quaternary.opacity(0.5))
        )
    }

    private func pickFile() {
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
            onMenuUpdate?()
        }
    }
}
