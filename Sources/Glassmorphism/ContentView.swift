import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var delegate: AppDelegate
    @ObservedObject var state: AppState
    @State private var isTargeted = false

    var body: some View {
        HSplitView {
            CanvasView(state: state)
                .frame(minWidth: 420)
                .overlay {
                    if isTargeted {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
                            .padding(8)
                            .allowsHitTesting(false)
                    }
                }

            InspectorView(state: state)
        }
        .frame(minWidth: 900, minHeight: 600)
        .onDrop(of: [.fileURL, .image], isTargeted: $isTargeted, perform: handleDrop)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    openImage()
                } label: {
                    Label(state.s.open, systemImage: "folder")
                }
                .keyboardShortcut("o", modifiers: .command)
                .help(state.s.openHelp)

                Spacer()

                Button {
                    state.copyToPasteboard()
                } label: {
                    Label(state.s.copy, systemImage: "doc.on.doc")
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(!state.hasImage)
                .help(state.s.copyHelp)

                Button {
                    state.exportPNG()
                } label: {
                    Label(state.s.exportPNG, systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!state.hasImage)
                .help(state.s.exportHelp)
            }
        }
        .safeAreaInset(edge: .bottom) {
            StatusBar(state: state)
        }
        .onReceive(delegate.$pendingURL.compactMap { $0 }) { url in
            state.load(url: url)
        }
        // 面板的任何變動（拖動、縮放、滑桿）都從這裡統一觸發重繪
        .onChange(of: state.panels) { _ in state.refreshPreview() }
    }

    // MARK: - 載入

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async { state.load(url: url) }
            }
            return true
        }

        // 從瀏覽器等來源直接拖圖（沒有檔案路徑）
        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
            guard let data,
                  let src = CGImageSourceCreateWithData(data as CFData, nil),
                  let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return }
            DispatchQueue.main.async { state.load(image: img, name: "dropped") }
        }
        return true
    }

    private func openImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            state.load(url: url)
        }
    }
}

private struct StatusBar: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(spacing: 8) {
            if state.hasImage {
                Image(systemName: "photo")
                Text(state.sourceName).lineLimit(1)
                Text("·").foregroundStyle(.tertiary)
            }
            Text(state.statusMessage ?? (state.hasImage ? state.s.statusHint : state.s.statusWaiting))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}
