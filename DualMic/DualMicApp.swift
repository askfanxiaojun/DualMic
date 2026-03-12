//
//  DualMicApp.swift
//  DualMic
//
//  Created by 樊笑君 on 3/11/26.
//

import SwiftUI
import AppKit

@main
struct DualMicApp: App {

    /// Single shared recorder — injected via environment into both scenes.
    @State private var recorder = AudioRecorder()

    /// Persists across launches via UserDefaults.
    @AppStorage("menuBarMode") private var menuBarMode = false

    init() {
        // Restore activation policy as soon as NSApp is ready. Cannot call
        // NSApp directly in init() because the NSApplication singleton has
        // not been created yet at this point (NSApp is nil → crash).
        if UserDefaults.standard.bool(forKey: "menuBarMode") {
            DispatchQueue.main.async {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    var body: some Scene {
        // Main window — always declared so SwiftUI can reopen it via openWindow.
        WindowGroup(id: "main-window") {
            ContentView()
                .environment(recorder)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 460, height: 480)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        // Menu bar icon — always present regardless of mode.
        // In normal mode it is a convenient shortcut; in menu bar mode it is the
        // primary entry point (the main window is hidden / not open).
        MenuBarExtra {
            ContentView()
                .environment(recorder)
        } label: {
            MenuBarLabel(isRecording: recorder.isRecording, isMixing: recorder.isMixing)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Menu Bar Status Label

private struct MenuBarLabel: View {
    let isRecording: Bool
    let isMixing: Bool

    var body: some View {
        Group {
            if isMixing {
                Image(systemName: "waveform.circle")
                    .foregroundStyle(.orange)
            } else if isRecording {
                Image(systemName: "waveform.badge.mic")
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse)
            } else {
                Image(systemName: "mic")
                    .foregroundStyle(.primary)
            }
        }
        .help(isMixing ? "DualMic — 正在处理音频" : isRecording ? "DualMic — 正在录音" : "DualMic")
    }
}
