import AppKit
import SwiftUI

/// 處理「用本 App 開啟圖片」（Finder 雙擊、open -a、拖到 Dock 圖示）
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published var pendingURL: URL?

    func application(_ application: NSApplication, open urls: [URL]) {
        pendingURL = urls.first
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct GlassApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState()

    private func addPhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { state.addPhoto(url: url) }
    }

    var body: some Scene {
        WindowGroup(state.s.windowTitle) {
            ContentView(state: state)
                .environmentObject(delegate)
        }
        .windowToolbarStyle(.unified)
        .commands {
            // ⌘N 改成「新增面板」，這個 App 沒有「新文件」的概念
            CommandGroup(replacing: .newItem) {
                Button(state.s.newPanel) { state.addPanel() }
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(!state.hasImage)
            }
            CommandGroup(after: .newItem) {
                Button(state.s.addPhoto) { addPhoto() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                    .disabled(!state.hasImage)
            }
            CommandMenu(state.s.menuPanel) {
                Button(state.s.duplicatePanel) { state.duplicateSelected() }
                    .keyboardShortcut("d", modifiers: .command)
                Button(state.s.deletePanel) { state.deleteSelected() }
                    .keyboardShortcut(.delete, modifiers: .command)
                Divider()
                Button(state.s.bringForward) { state.moveSelected(up: true) }
                    .keyboardShortcut("]", modifiers: .command)
                Button(state.s.sendBackward) { state.moveSelected(up: false) }
                    .keyboardShortcut("[", modifiers: .command)
                Button(state.s.toTop) { state.sendSelected(toTop: true) }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
                Button(state.s.toBottom) { state.sendSelected(toTop: false) }
                    .keyboardShortcut("[", modifiers: [.command, .shift])
            }
            CommandMenu(state.s.menuLanguage) {
                Picker(state.s.menuLanguage, selection: $state.language) {
                    ForEach(Language.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .pickerStyle(.inline)
            }
        }
    }
}
