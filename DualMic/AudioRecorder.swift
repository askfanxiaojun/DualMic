//
//  AudioRecorder.swift
//  DualMic
//
//  Created by 樊笑君 on 3/11/26.
//

import Foundation
import AVFoundation
import ScreenCaptureKit
import Accelerate
import Observation
import CoreGraphics
import CoreAudio

// MARK: - Supporting Types

struct AudioInputDevice: Identifiable, Equatable {
    let id: AudioDeviceID   // UInt32 — CoreAudio native identifier
    let name: String
}

// MARK: - Error Types

enum RecordingError: LocalizedError {
    case noMicPermission
    case noDisplayFound
    case invalidURL
    case mixFailed

    var errorDescription: String? {
        switch self {
        case .noMicPermission:
            return "需要麦克风权限，请在系统设置 → 隐私与安全性 → 麦克风 中授权"
        case .noDisplayFound:
            return "未找到显示器，无法捕获系统声音"
        case .invalidURL:
            return "录音文件路径无效"
        case .mixFailed:
            return "音频混合导出失败"
        }
    }
}

// MARK: - AudioRecorder

@Observable
class AudioRecorder: NSObject {

    // MARK: Published UI State (MainActor by default)

    var isRecording = false
    var isPaused = false
    var isMixing = false
    var micLevel: Float = 0.0
    var sysLevel: Float = 0.0
    var recordingDuration: TimeInterval = 0.0
    var outputFileURL: URL?
    var statusMessage = "准备就绪"
    var errorMessage: String?
    var hasMicPermission = false
    var hasScreenPermission = false
    var recordSystemAudio = true

    // Input device list & selection (nil = system default)
    var availableInputDevices: [AudioInputDevice] = []
    var selectedInputDeviceID: AudioDeviceID? = nil

    // MARK: Private Audio Engine State

    private var audioEngine = AVAudioEngine()
    private var scStream: SCStream?
    private var recordingTimer: Timer?

    // Multi-segment timer: supports pause/resume without gaps in the timestamp.
    private var accumulatedDuration: TimeInterval = 0
    private var segmentStart: Date? = nil

    private var micTempURL: URL?
    private var sysTempURL: URL?

    // File handles & pause flag accessed from background audio threads.
    // Protected by audioLock; @ObservationIgnored prevents macro-generated
    // observation tracking on these internal-only properties.
    @ObservationIgnored nonisolated(unsafe) private var _micFile: AVAudioFile?
    @ObservationIgnored nonisolated(unsafe) private var _sysFile: AVAudioFile?
    // Renamed to avoid collision with @Observable macro's auto-generated _isPaused backing storage.
    @ObservationIgnored nonisolated(unsafe) private var _audioThreadPaused = false
    @ObservationIgnored nonisolated private let audioLock = NSLock()

    // First-frame timestamps used to compensate for the SCKit async startup offset.
    @ObservationIgnored nonisolated(unsafe) private var _micFirstFrameDate: Date? = nil
    @ObservationIgnored nonisolated(unsafe) private var _sysFirstFrameDate: Date? = nil

    // MARK: - Permissions

    func checkPermissions() async {
        // Microphone: show system dialog on first ask.
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            hasMicPermission = true
        case .notDetermined:
            hasMicPermission = await AVCaptureDevice.requestAccess(for: .audio)
        default:
            hasMicPermission = false
        }

        if hasMicPermission {
            refreshInputDevices()
        }

        // Screen recording: silent TCC preflight, no dialog.
        if CGPreflightScreenCaptureAccess() {
            hasScreenPermission = true
            return
        }

        // First launch: auto-trigger the TCC sheet so the app is registered in
        // System Settings → Privacy → Screen Recording. After that, only check
        // silently (avoids repeated pop-ups if the user dismissed the dialog).
        let promptedKey = "dualmic.hasPromptedScreenRecording"
        if !UserDefaults.standard.bool(forKey: promptedKey) {
            UserDefaults.standard.set(true, forKey: promptedKey)
            await requestScreenCapturePermission()
        } else {
            hasScreenPermission = false
        }
    }

    /// Called when the user explicitly tries to enable system audio.
    /// Triggers the TCC consent dialog exactly once (first install / new signature),
    /// so the app registers in System Settings → Privacy → Screen Recording.
    func requestScreenCapturePermission() async {
        if CGPreflightScreenCaptureAccess() {
            hasScreenPermission = true
            return
        }
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            hasScreenPermission = true
        } catch {
            hasScreenPermission = CGPreflightScreenCaptureAccess()
        }
    }

    // MARK: - Input Device Enumeration

    func refreshInputDevices() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize
        ) == noErr else { return }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return }
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceIDs
        ) == noErr else { return }

        var result: [AudioInputDevice] = []
        for deviceID in deviceIDs {
            // Check input channel count via stream configuration.
            var streamAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioObjectPropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(deviceID, &streamAddr, 0, nil, &streamSize) == noErr,
                  streamSize >= UInt32(MemoryLayout<AudioBufferList>.size) else { continue }

            let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
            defer { bufferList.deallocate() }
            guard AudioObjectGetPropertyData(
                deviceID, &streamAddr, 0, nil, &streamSize, bufferList
            ) == noErr else { continue }

            // Skip devices with no input channels.
            let mBuffers = UnsafeMutableAudioBufferListPointer(bufferList)
            let totalChannels = mBuffers.reduce(0) { $0 + Int($1.mNumberChannels) }
            guard totalChannels > 0 else { continue }

            // Fetch device name via an Unmanaged<CFString> to satisfy
            // AudioObjectGetPropertyData's UnsafeMutableRawPointer requirement.
            var nameAddr = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var unmanagedName: Unmanaged<CFString>? = nil
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            let nameStatus = withUnsafeMutablePointer(to: &unmanagedName) { ptr in
                AudioObjectGetPropertyData(
                    deviceID, &nameAddr, 0, nil, &nameSize,
                    UnsafeMutableRawPointer(ptr)
                )
            }
            guard nameStatus == noErr, let deviceName = unmanagedName?.takeRetainedValue() else { continue }

            result.append(AudioInputDevice(id: deviceID, name: deviceName as String))
        }

        availableInputDevices = result

        // If the previously selected device is no longer present, reset to default.
        if let sel = selectedInputDeviceID, !result.contains(where: { $0.id == sel }) {
            selectedInputDeviceID = nil
        }
    }

    // MARK: - Recording Control

    func startRecording() async throws {
        guard hasMicPermission else { throw RecordingError.noMicPermission }

        errorMessage = nil
        recordingDuration = 0
        accumulatedDuration = 0
        segmentStart = nil
        outputFileURL = nil
        isPaused = false
        _micFirstFrameDate = nil
        _sysFirstFrameDate = nil

        let timestamp = Int(Date().timeIntervalSince1970)
        let tmpDir = FileManager.default.temporaryDirectory
        micTempURL = tmpDir.appendingPathComponent("dualmic_mic_\(timestamp).wav")
        sysTempURL = tmpDir.appendingPathComponent("dualmic_sys_\(timestamp).wav")

        try setupMicRecording()
        if recordSystemAudio {
            try await setupSystemAudioRecording()
        }

        segmentStart = Date()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            if !self.isPaused, let start = self.segmentStart {
                self.recordingDuration = self.accumulatedDuration + Date().timeIntervalSince(start)
            }
            if !self.isPaused {
                self.micLevel *= 0.88
                self.sysLevel *= 0.88
            }
        }

        isRecording = true
        statusMessage = recordSystemAudio ? "正在录音（麦克风 + 系统声音）..." : "正在录音（仅麦克风）..."
    }

    func pauseRecording() {
        guard isRecording && !isPaused else { return }

        // Tell the SCStream audio thread to stop writing before pausing the engine.
        audioLock.lock(); _audioThreadPaused = true; audioLock.unlock()

        // Pausing the engine stops mic tap callbacks synchronously.
        audioEngine.pause()

        // Accumulate this segment's duration.
        if let start = segmentStart {
            accumulatedDuration += Date().timeIntervalSince(start)
            segmentStart = nil
        }

        isPaused = true
        micLevel = 0
        sysLevel = 0
        statusMessage = "已暂停"
    }

    func resumeRecording() {
        guard isRecording && isPaused else { return }

        do {
            try audioEngine.start()
        } catch {
            errorMessage = "恢复录音失败：\(error.localizedDescription)"
            return
        }

        segmentStart = Date()
        audioLock.lock(); _audioThreadPaused = false; audioLock.unlock()
        isPaused = false
        statusMessage = recordSystemAudio ? "正在录音（麦克风 + 系统声音）..." : "正在录音（仅麦克风）..."
    }

    func stopRecording() async throws -> URL {
        // Safe to set directly without the lock: the engine and stream are stopped
        // immediately below, so no audio callbacks can race against this write.
        _audioThreadPaused = false
        isPaused = false

        isRecording = false
        recordingTimer?.invalidate()
        recordingTimer = nil

        // Accumulate any remaining active segment before stopping.
        if let start = segmentStart {
            accumulatedDuration += Date().timeIntervalSince(start)
            segmentStart = nil
        }

        // Stop microphone tap — removeTap waits for the current render cycle.
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()

        // Stop system audio stream.
        try? await scStream?.stopCapture()
        scStream = nil

        // Both streams are fully stopped — no more callbacks can fire.
        // Nil out the file handles to flush and close them.
        _micFile = nil
        _sysFile = nil

        micLevel = 0
        sysLevel = 0
        isMixing = true
        statusMessage = "正在混合导出..."

        guard let micURL = micTempURL, let sysURL = sysTempURL else {
            isMixing = false
            throw RecordingError.invalidURL
        }

        let shouldMixSys = recordSystemAudio

        // Calculate how many seconds after the mic's first frame the sys audio
        // first arrived. This compensates for the async SCKit setup window.
        let micFirst = _micFirstFrameDate
        let sysFirst = _sysFirstFrameDate
        let sysOffsetSeconds: Double
        if let mic = micFirst, let sys = sysFirst {
            sysOffsetSeconds = sys.timeIntervalSince(mic)
        } else {
            sysOffsetSeconds = 0
        }

        let outputURL = try await Task.detached(priority: .userInitiated) {
            try Self.mixAudio(
                micURL: micURL,
                sysURL: sysURL,
                includeSysAudio: shouldMixSys,
                sysOffsetSeconds: sysOffsetSeconds
            )
        }.value

        isMixing = false
        outputFileURL = outputURL
        statusMessage = "录音完成"
        return outputURL
    }

    // MARK: - Microphone Setup

    private func setupMicRecording() throws {
        // Apply selected input device before starting the engine.
        if let deviceID = selectedInputDeviceID,
           let audioUnit = audioEngine.inputNode.audioUnit {
            var id = deviceID
            AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global, 0,
                &id, UInt32(MemoryLayout<AudioDeviceID>.size)
            )
        }

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard let micURL = micTempURL else { throw RecordingError.invalidURL }

        _micFile = try AVAudioFile(forWriting: micURL, settings: inputFormat.settings)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }

            self.audioLock.lock()
            if !self._audioThreadPaused {
                if self._micFirstFrameDate == nil { self._micFirstFrameDate = Date() }
                try? self._micFile?.write(from: buffer)
            }
            self.audioLock.unlock()

            guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            var rms: Float = 0
            vDSP_measqv(data, 1, &rms, vDSP_Length(buffer.frameLength))
            let level = min(1.0, sqrt(rms) * 6.0)
            Task { @MainActor [weak self] in
                self?.micLevel = max(self?.micLevel ?? 0, level)
            }
        }

        try audioEngine.start()
    }

    // MARK: - System Audio Setup

    private func setupSystemAudioRecording() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first else { throw RecordingError.noDisplayFound }

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.sampleRate = 48000
        config.channelCount = 2
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])

        // _sysFile is created lazily in the stream() callback using the actual
        // delivered buffer format, so there is no sample-rate mismatch.

        scStream = SCStream(filter: filter, configuration: config, delegate: self)
        try scStream?.addStreamOutput(
            self,
            type: .audio,
            sampleHandlerQueue: DispatchQueue(label: "com.dualmic.sysaudio", qos: .userInitiated)
        )
        try await scStream?.startCapture()
    }

    // MARK: - Offline Mix & Export (static, runs on background thread)

    private static nonisolated func mixAudio(
        micURL: URL,
        sysURL: URL,
        includeSysAudio: Bool = true,
        sysOffsetSeconds: Double = 0
    ) throws -> URL {
        let tmpDir = FileManager.default.temporaryDirectory
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let outputURL = tmpDir.appendingPathComponent("DualMic_\(formatter.string(from: Date())).m4a")

        let micFile = try AVAudioFile(forReading: micURL)

        let hasSysAudio: Bool
        if includeSysAudio,
           FileManager.default.fileExists(atPath: sysURL.path),
           let f = try? AVAudioFile(forReading: sysURL), f.length > 0 {
            hasSysAudio = true
        } else {
            hasSysAudio = false
        }

        // Use 48000 Hz to match macOS hardware rate; avoids SRC in the render pass.
        let outputFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        let renderEngine = AVAudioEngine()
        let micPlayer = AVAudioPlayerNode()
        renderEngine.attach(micPlayer)
        renderEngine.connect(micPlayer, to: renderEngine.mainMixerNode, format: micFile.processingFormat)

        var sysPlayer: AVAudioPlayerNode?
        var sysFile: AVAudioFile?
        if hasSysAudio {
            let sf = try AVAudioFile(forReading: sysURL)
            sysFile = sf
            let sp = AVAudioPlayerNode()
            sysPlayer = sp
            renderEngine.attach(sp)
            renderEngine.connect(sp, to: renderEngine.mainMixerNode, format: sf.processingFormat)
        }

        renderEngine.connect(renderEngine.mainMixerNode, to: renderEngine.outputNode, format: outputFormat)
        try renderEngine.enableManualRenderingMode(.offline, format: outputFormat, maximumFrameCount: 4096)
        try renderEngine.start()

        micPlayer.play()
        micPlayer.scheduleFile(micFile, at: nil)
        if let sp = sysPlayer, let sf = sysFile {
            sp.play()
            // Delay sys track by sysOffsetSeconds to compensate for the async SCKit
            // setup window during which the mic was already recording.
            let clampedOffset = max(0, sysOffsetSeconds)
            if clampedOffset > 0 {
                let offsetSamples = AVAudioFramePosition(clampedOffset * outputFormat.sampleRate)
                let startTime = AVAudioTime(sampleTime: offsetSamples, atRate: outputFormat.sampleRate)
                sp.scheduleFile(sf, at: startTime)
            } else {
                sp.scheduleFile(sf, at: nil)
            }
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 192000
        ]
        let outputFile = try AVAudioFile(forWriting: outputURL, settings: outputSettings)

        let renderBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 4096)!

        // Normalize frame counts to output sample rate before comparing durations,
        // so that tracks recorded at different hardware rates align correctly.
        let micDuration = Double(micFile.length) / micFile.processingFormat.sampleRate
        let rawSysDuration = sysFile.map { Double($0.length) / $0.processingFormat.sampleRate } ?? 0
        let sysEndTime = max(0, sysOffsetSeconds) + rawSysDuration
        let totalFrames = AVAudioFramePosition(max(micDuration, sysEndTime) * outputFormat.sampleRate)
        var rendered: AVAudioFramePosition = 0

        while rendered < totalFrames {
            let toRender = AVAudioFrameCount(min(4096, totalFrames - rendered))
            renderBuffer.frameLength = toRender
            let status = try renderEngine.renderOffline(toRender, to: renderBuffer)
            switch status {
            case .success:
                try outputFile.write(from: renderBuffer)
                rendered += AVAudioFramePosition(toRender)
            case .insufficientDataFromInputNode:
                if renderBuffer.frameLength > 0 { try outputFile.write(from: renderBuffer) }
                rendered = totalFrames
            case .cannotDoInCurrentContext, .error:
                throw RecordingError.mixFailed
            @unknown default:
                throw RecordingError.mixFailed
            }
        }

        renderEngine.stop()

        try? FileManager.default.removeItem(at: micURL)
        try? FileManager.default.removeItem(at: sysURL)

        return outputURL
    }
}

// MARK: - SCStreamOutput

extension AudioRecorder: SCStreamOutput {

    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .audio else { return }
        guard let pcmBuffer = Self.extractPCMBuffer(from: sampleBuffer) else { return }

        audioLock.lock()
        if !_audioThreadPaused {
            if _sysFirstFrameDate == nil { _sysFirstFrameDate = Date() }
            if _sysFile == nil, let sysURL = sysTempURL {
                _sysFile = try? AVAudioFile(forWriting: sysURL, settings: pcmBuffer.format.settings)
            }
            try? _sysFile?.write(from: pcmBuffer)
        }
        audioLock.unlock()

        guard let data = pcmBuffer.floatChannelData?[0], pcmBuffer.frameLength > 0 else { return }
        var rms: Float = 0
        vDSP_measqv(data, 1, &rms, vDSP_Length(pcmBuffer.frameLength))
        let level = min(1.0, sqrt(rms) * 6.0)
        Task { @MainActor [weak self] in
            self?.sysLevel = max(self?.sysLevel ?? 0, level)
        }
    }

    private static nonisolated func extractPCMBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDesc = sampleBuffer.formatDescription,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc),
              let audioFormat = AVAudioFormat(streamDescription: asbd) else { return nil }

        let frameCount = AVAudioFrameCount(sampleBuffer.numSamples)
        guard frameCount > 0,
              let pcmBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCount) else { return nil }
        pcmBuffer.frameLength = frameCount

        guard let dataBuffer = sampleBuffer.dataBuffer else { return nil }
        let totalBytes = CMBlockBufferGetDataLength(dataBuffer)
        guard totalBytes > 0 else { return nil }

        let channelCount = Int(audioFormat.channelCount)

        if audioFormat.isInterleaved {
            guard let dst = pcmBuffer.floatChannelData?[0] else { return nil }
            CMBlockBufferCopyDataBytes(dataBuffer, atOffset: 0, dataLength: totalBytes,
                                      destination: UnsafeMutableRawPointer(dst))
        } else {
            let bytesPerChannel = totalBytes / max(channelCount, 1)
            for ch in 0..<channelCount {
                guard let dst = pcmBuffer.floatChannelData?[ch] else { continue }
                CMBlockBufferCopyDataBytes(dataBuffer, atOffset: ch * bytesPerChannel,
                                          dataLength: bytesPerChannel,
                                          destination: UnsafeMutableRawPointer(dst))
            }
        }

        return pcmBuffer
    }
}

// MARK: - SCStreamDelegate

extension AudioRecorder: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.errorMessage = "系统声音录制中断：\(error.localizedDescription)"
            self?.statusMessage = "录制出错"
        }
    }
}
