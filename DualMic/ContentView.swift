//
//  ContentView.swift
//  DualMic
//
//  Created by 樊笑君 on 3/11/26.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit
import CoreAudio

struct ContentView: View {
    @Environment(AudioRecorder.self) private var recorder
    @AppStorage("menuBarMode") private var menuBarMode = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            if !recorder.isRecording && !recorder.isMixing && needsPermissionGuide {
                Divider()
                permissionBannerSection
            }
            Divider()
            levelMetersSection
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            Divider()
            timerSection
                .padding(.vertical, 20)
            Divider()
            controlsSection
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            if recorder.outputFileURL != nil || recorder.errorMessage != nil {
                Divider()
                bottomSection
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
            }
            Divider()
            footerSection
        }
        .frame(width: 460)
        .task {
            await recorder.checkPermissions()
        }
        // Re-check permissions whenever the app regains focus (e.g. user returns
        // from System Settings after granting screen recording permission).
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await recorder.checkPermissions() }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(recorder.isRecording ? Color.red.opacity(0.15) : Color.accentColor.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: "waveform.badge.mic")
                    .font(.title2)
                    .foregroundStyle(recorder.isRecording ? .red : .accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("DualMic")
                    .font(.title3.bold())
                Text(recorder.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .animation(.easeInOut, value: recorder.statusMessage)
            }

            Spacer()

            HStack(spacing: 10) {
                PermissionBadge(
                    icon: "mic.fill",
                    label: "麦克风",
                    granted: recorder.hasMicPermission
                )
                PermissionBadge(
                    icon: "display",
                    label: "屏幕录制",
                    granted: recorder.hasScreenPermission
                )
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Permission Banner

    private var needsPermissionGuide: Bool {
        !recorder.hasMicPermission || !recorder.hasScreenPermission
    }

    private var permissionBannerSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 3) {
                    Text("需要以下权限才能开始录音")
                        .font(.callout.bold())
                    Text(permissionBannerDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)

            HStack(spacing: 10) {
                if !recorder.hasMicPermission {
                    Button {
                        openPrivacySettings("Privacy_Microphone")
                    } label: {
                        Label("授权麦克风", systemImage: "mic.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .controlSize(.small)
                }

                if !recorder.hasScreenPermission {
                    Button {
                        Task {
                            await recorder.requestScreenCapturePermission()
                            if !recorder.hasScreenPermission {
                                openPrivacySettings("Privacy_ScreenCapture")
                            }
                        }
                    } label: {
                        Label("授权屏幕录制", systemImage: "display")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.small)
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .background(Color.orange.opacity(0.07))
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.25), value: needsPermissionGuide)
    }

    private var permissionBannerDetail: String {
        if !recorder.hasMicPermission && !recorder.hasScreenPermission {
            return "麦克风 · 屏幕录制（系统声音）均未授权"
        } else if !recorder.hasMicPermission {
            return "麦克风未授权，无法录制任何音频"
        } else {
            return "屏幕录制未授权，系统声音将无法录制"
        }
    }

    // MARK: - Level Meters

    private var levelMetersSection: some View {
        VStack(spacing: 14) {
            LevelMeterRow(
                icon: "mic.fill",
                label: "麦克风",
                level: recorder.micLevel,
                tint: .blue
            )

            // Input device picker — only shown when not recording and more than one device available
            if !recorder.isRecording && !recorder.isMixing && recorder.availableInputDevices.count > 1 {
                devicePickerRow
            }

            LevelMeterRow(
                icon: "speaker.wave.3.fill",
                label: "系统声音",
                level: recorder.sysLevel,
                tint: .green,
                isEnabled: recorder.recordSystemAudio,
                onToggle: { enabled in
                    if !recorder.hasScreenPermission && enabled {
                        // Trigger TCC dialog (first install) then open System Settings.
                        Task {
                            await recorder.requestScreenCapturePermission()
                            if !recorder.hasScreenPermission {
                                openPrivacySettings("Privacy_ScreenCapture")
                            } else {
                                recorder.recordSystemAudio = true
                            }
                        }
                    } else {
                        recorder.recordSystemAudio = enabled
                    }
                },
                canToggle: !recorder.isRecording && !recorder.isMixing
            )
        }
    }

    private var devicePickerRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "mic.circle")
                .frame(width: 18)
                .foregroundStyle(.secondary)

            Text("输入设备")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)

            Picker("", selection: Binding(
                get: { recorder.selectedInputDeviceID },
                set: { recorder.selectedInputDeviceID = $0 }
            )) {
                Text("系统默认").tag(AudioDeviceID?.none)
                ForEach(recorder.availableInputDevices) { device in
                    Text(device.name).tag(Optional(device.id))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .controlSize(.small)
        }
    }

    // MARK: - Timer

    private var timerSection: some View {
        Text(formattedDuration(recorder.recordingDuration))
            .font(.system(size: 52, weight: .thin, design: .monospaced))
            .foregroundStyle(
                recorder.isPaused ? Color.orange
                    : recorder.isRecording ? Color.red
                    : Color.primary
            )
            .contentTransition(.numericText())
            .animation(.easeInOut(duration: 0.2), value: recorder.isRecording)
            .animation(.easeInOut(duration: 0.2), value: recorder.isPaused)
    }

    // MARK: - Controls

    private var controlsSection: some View {
        HStack(spacing: 20) {
            recordButton

            // Pause / Resume button — only visible while recording
            if recorder.isRecording {
                pauseButton
            }

            VStack(alignment: .leading, spacing: 6) {
                if recorder.isMixing {
                    Label("正在处理音频，请稍候...", systemImage: "gear.circle")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else if recorder.isPaused {
                    Label("已暂停 — 点击继续", systemImage: "play.circle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                } else if recorder.isRecording {
                    Label("点击停止并保存录音", systemImage: "stop.circle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                } else if recorder.recordSystemAudio {
                    Label("点击开始录制麦克风 + 系统声音", systemImage: "record.circle")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    Label("点击开始录制（仅麦克风）", systemImage: "record.circle")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }

                permissionWarnings
            }

            Spacer()
        }
    }

    private var pauseButton: some View {
        Button(action: handlePauseButton) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: recorder.isPaused ? "play.fill" : "pause.fill")
                    .font(.body)
                    .foregroundStyle(.orange)
            }
        }
        .buttonStyle(.plain)
        .help(recorder.isPaused ? "继续录音" : "暂停录音")
        .transition(.scale.combined(with: .opacity))
        .animation(.easeInOut(duration: 0.2), value: recorder.isPaused)
    }

    private var recordButton: some View {
        Button(action: handleRecordButton) {
            ZStack {
                Circle()
                    .fill(buttonColor)
                    .frame(width: 64, height: 64)
                    .shadow(color: buttonColor.opacity(0.4), radius: recorder.isRecording ? 8 : 0)
                    .animation(.easeInOut(duration: 0.3), value: recorder.isRecording)

                if recorder.isMixing {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                } else if recorder.isRecording {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(.white)
                        .frame(width: 22, height: 22)
                } else {
                    Image(systemName: "mic.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(recorder.isMixing || !canRecord)
        .help(recorder.isRecording ? "停止录音" : "开始录音")
    }

    @ViewBuilder
    private var permissionWarnings: some View {
        if !recorder.hasMicPermission {
            Button("前往授权麦克风权限") {
                openPrivacySettings("Privacy_Microphone")
            }
            .buttonStyle(.link)
            .font(.caption)
        }
    }

    // MARK: - Bottom Section (output / error)

    @ViewBuilder
    private var bottomSection: some View {
        if let url = recorder.outputFileURL {
            OutputFileRow(url: url) { newURL in
                recorder.outputFileURL = newURL
            } onError: { msg in
                recorder.errorMessage = msg
            }
        }
        if let msg = recorder.errorMessage {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                Spacer()
                Button {
                    recorder.errorMessage = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Footer (mode toggle)

    private var footerSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "menubar.rectangle")
                .foregroundStyle(.secondary)
                .font(.callout)

            Text("菜单栏模式")
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()

            Toggle("", isOn: $menuBarMode)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .disabled(recorder.isRecording || recorder.isMixing)
                .help(menuBarMode ? "切换回普通窗口模式，Dock 图标恢复显示" : "切换到菜单栏模式，隐藏 Dock 图标，通过菜单栏图标操作")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .onChange(of: menuBarMode) { _, enabled in
            if enabled {
                // Hide from Dock and close the main titled window.
                NSApp.setActivationPolicy(.accessory)
                NSApp.windows
                    .filter { $0.styleMask.contains(.titled) }
                    .forEach { $0.close() }
            } else {
                // Restore Dock icon and reopen the main window.
                NSApp.setActivationPolicy(.regular)
                openWindow(id: "main-window")
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    // MARK: - Helpers

    private var canRecord: Bool {
        recorder.hasMicPermission && (!recorder.recordSystemAudio || recorder.hasScreenPermission)
    }

    private var buttonColor: Color {
        if recorder.isMixing { return .secondary }
        if recorder.isRecording { return .red }
        return canRecord ? .accentColor : .secondary
    }

    private func formattedDuration(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600
        let m = Int(t) / 60 % 60
        let s = Int(t) % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    private func handleRecordButton() {
        if recorder.isRecording {
            Task {
                do {
                    _ = try await recorder.stopRecording()
                } catch {
                    recorder.errorMessage = error.localizedDescription
                }
            }
        } else {
            Task {
                do {
                    try await recorder.startRecording()
                } catch {
                    recorder.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func handlePauseButton() {
        if recorder.isPaused {
            recorder.resumeRecording()
        } else {
            recorder.pauseRecording()
        }
    }

    private func openPrivacySettings(_ section: String) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(section)")!
        NSWorkspace.shared.open(url)
    }
}

// MARK: - LevelMeterRow

private struct LevelMeterRow: View {
    let icon: String
    let label: String
    let level: Float
    let tint: Color
    var isEnabled: Bool = true
    /// nil = not tappable; non-nil = called when label is tapped to toggle
    var onToggle: ((Bool) -> Void)? = nil
    /// Whether the tap interaction is allowed (e.g. locked during recording)
    var canToggle: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 18)
                .foregroundStyle(isEnabled && level > 0.01 ? tint : .secondary)
                .animation(.easeInOut(duration: 0.1), value: level > 0.01)

            // Tappable label: strikethrough when disabled
            labelView

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.15))

                    if isEnabled {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(meterGradient)
                            .frame(width: max(4, geo.size.width * CGFloat(level)))
                            .animation(.easeOut(duration: 0.06), value: level)
                    }
                }
            }
            .frame(height: 14)
            .opacity(isEnabled ? 1.0 : 0.35)

            Text(isEnabled ? String(format: "%3.0f%%", level * 100) : "—")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)
                .opacity(isEnabled ? 1.0 : 0.35)
        }
    }

    @ViewBuilder
    private var labelView: some View {
        if let onToggle {
            Text(label)
                .font(.caption)
                .foregroundStyle(isEnabled ? .secondary : Color.secondary.opacity(0.45))
                .strikethrough(!isEnabled, color: .secondary)
                .frame(width: 56, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    if canToggle { onToggle(!isEnabled) }
                }
                .help(canToggle
                    ? (isEnabled ? "点击关闭系统声音录制" : "点击开启系统声音录制")
                    : "录音进行中，无法更改"
                )
        } else {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
        }
    }

    private var meterGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: tint.opacity(0.7), location: 0.0),
                .init(color: tint, location: 0.6),
                .init(color: .orange, location: 0.85),
                .init(color: .red, location: 1.0)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - PermissionBadge

private struct PermissionBadge: View {
    let icon: String
    let label: String
    let granted: Bool

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: granted ? icon : "\(icon).slash")
                .font(.callout)
                .foregroundStyle(granted ? .green : .secondary)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(granted ? .green : .secondary)
        }
        .help(granted ? "\(label)权限已授权" : "\(label)权限未授权")
    }
}

// MARK: - OutputFileRow

private struct OutputFileRow: View {
    let url: URL
    let onSaved: (URL) -> Void
    let onError: (String) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .font(.callout.bold())
                    .lineLimit(1)
                Text("临时目录 — 点击「存储」保存到指定位置")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("在 Finder 中显示") {
                NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button("存储...") {
                presentSavePanel(for: url)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(12)
        .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.green.opacity(0.2), lineWidth: 1)
        )
    }

    private func presentSavePanel(for sourceURL: URL) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = sourceURL.lastPathComponent
        panel.allowedContentTypes = [UTType.mpeg4Audio]
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let dest = panel.url else { return }
            do {
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.copyItem(at: sourceURL, to: dest)
                onSaved(dest)
            } catch {
                onError("保存失败：\(error.localizedDescription)")
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(AudioRecorder())
}
