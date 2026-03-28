//
//  VoiceEngine.swift
//  Vectormac
//
//  Speech recognition + synthesis — Jarvis's ears and voice
//

import Foundation
import Speech
import AVFoundation

class VoiceEngine: ObservableObject {
    
    @Published var isListening = false
    @Published var isSpeaking = false
    @Published var statusText = "STANDBY"
    @Published var transcript: [(role: String, text: String)] = []
    @Published var currentHearing = ""
    @Published var audioLevel: CGFloat = 0
    
    private let brain = GroqBrain.shared
    private let systemUtils = SystemUtils.shared
    
    private var audioRecorder: AVAudioRecorder?
    private var levelTimer: Timer?
    private var silenceDuration: TimeInterval = 0
    private var isProcessing = false
    private var speakProcess: Process?
    
    private let tempAudioURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("jarvis_recording.m4a")
    
    init() { }
    
    // MARK: - Speech (macOS say)
    
    func speak(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isSpeaking = true
            self.statusText = "SPEAKING"
            self.transcript.append((role: "jarvis", text: text))
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            process.arguments = ["-v", "Daniel", "-r", "195", text]
            try? process.run()
            process.waitUntilExit()
            DispatchQueue.main.async {
                self.isSpeaking = false
                self.isProcessing = false
                self.statusText = "STANDBY"
            }
        }
    }
    
    // MARK: - Toggle
    
    func toggleListening() {
        if isSpeaking {
            speakProcess?.terminate()
            isSpeaking = false
            isProcessing = false
            statusText = "STANDBY"
            return
        }
        
        if isListening {
            stopRecordingAndProcess(manual: true)
        } else {
            startRecording()
        }
    }
    
    // MARK: - Recording & Silence Detection
    
    private func startRecording() {
        guard !isProcessing else { return }
        
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if granted {
                    self.beginRecordingSession()
                } else {
                    self.statusText = "MICROPHONE DENIED"
                }
            }
        }
    }
    
    private func beginRecordingSession() {
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: tempAudioURL, settings: settings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.prepareToRecord()
            audioRecorder?.record()
            
            isListening = true
            statusText = "LISTENING"
            currentHearing = ""
            silenceDuration = 0
            
            levelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.monitorAudioLevel()
            }
        } catch {
            statusText = "MIC INIT FAILED"
        }
    }
    
    private func monitorAudioLevel() {
        guard let recorder = audioRecorder, recorder.isRecording else { return }
        recorder.updateMeters()
        
        let power = recorder.averagePower(forChannel: 0) // range: -160 to 0
        
        // Power to 0.0 - 1.0 linear scale roughly
        let level = CGFloat(max(0, power + 50) / 50)
        self.audioLevel = min(level * 2, 1.0)
        
        if power < -35 {
            silenceDuration += 0.1
            if silenceDuration > 1.5 { // 1.5 seconds of silence
                stopRecordingAndProcess(manual: false)
            }
        } else {
            silenceDuration = 0 // User is talking
        }
    }
    
    private func stopRecordingAndProcess(manual: Bool) {
        guard isListening else { return }
        
        levelTimer?.invalidate()
        levelTimer = nil
        audioRecorder?.stop()
        isListening = false
        audioLevel = 0
        
        processRecording()
    }
    
    func stopListening() {
        levelTimer?.invalidate()
        levelTimer = nil
        audioRecorder?.stop()
        isListening = false
        audioLevel = 0
        if !isProcessing { statusText = "STANDBY" }
    }
    
    // MARK: - Process Audio via Groq Whisper
    
    private func processRecording() {
        guard !isProcessing else { return }
        isProcessing = true
        statusText = "TRANSCRIBING..."
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let transcript = self.transcribeWithWhisperSync()
            guard !transcript.isEmpty else {
                DispatchQueue.main.async {
                    self.statusText = "STANDBY"
                    self.isProcessing = false
                }
                return // User just tapped mic without speaking
            }
            
            DispatchQueue.main.async {
                self.currentHearing = transcript
                self.statusText = "HEARING: \(transcript)"
            }
            
            self.processCommandText(transcript)
        }
    }
    
    private func transcribeWithWhisperSync() -> String {
        guard let audioData = try? Data(contentsOf: tempAudioURL) else { return "" }
        
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(brain.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Model
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-large-v3\r\n".data(using: .utf8)!)
        
        // Force English Language
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
        body.append("en\r\n".data(using: .utf8)!)
        
        // File
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let semaphore = DispatchSemaphore(value: 0)
        var transcript = ""
        
        let task = URLSession.shared.dataTask(with: request) { data, _, _ in
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let text = json["text"] as? String {
                transcript = text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()
        
        return transcript
    }
    
    // MARK: - Answer command via Llama
    
    private func processCommandText(_ text: String) {
        DispatchQueue.main.async {
            self.transcript.append((role: "user", text: text))
        }
        
        // Local command check first
        if let localResponse = self.systemUtils.handleCommand(text) {
            DispatchQueue.main.async { self.statusText = "THINKING" }
            Thread.sleep(forTimeInterval: 0.3)
            self.speak(localResponse)
            return
        }
        
        // Groq AI brain
        DispatchQueue.main.async { self.statusText = "ASKING GROQ..." }
        
        let semaphore = DispatchSemaphore(value: 0)
        var response = "I had trouble reaching the neural network, sir."
        
        Task {
            response = await self.brain.ask(text)
            semaphore.signal()
        }
        
        semaphore.wait()
        self.speak(response)
    }
}
import Foundation
import AVFoundation
import SoundAnalysis
import CoreML

/// `ClapWakeEngine` listens for "Hand Clapping" using Apple's built-in `SoundAnalysis` framework.
///
/// **Efficiency & Apple Neural Engine (ANE) Utilization:**
/// Apple's `SNClassifySoundRequest` (`.version1`) runs natively on CoreML. On Apple Silicon (M-series),
/// this model is automatically offloaded to the highly efficient Apple Neural Engine (ANE).
/// The ANE uses significantly less power than the CPU, allowing this audio tap to run persistently
/// in the background without draining the battery or spinning up high-performance cores.
/// Furthermore, `AVAudioEngine` taps run asynchronously on low-priority real-time audio threads,
/// maximizing standby efficiency.
class ClapWakeEngine: NSObject, ObservableObject {
    
    private var audioEngine: AVAudioEngine?
    private var streamAnalyzer: SNAudioStreamAnalyzer?
    private var isListening = false
    
    // Callback to trigger when clap is detected
    var onClapDetected: (() -> Void)?
    
    // An internal queue to process Sound Analysis results off the main thread
    private let analysisQueue = DispatchQueue(label: "com.jarvis.soundanalysis", qos: .userInteractive)
    
    // Prevent multiple triggers from a single clap sequence
    private var lastClapTime: Date = Date.distantPast
    
    /// Requests microphone permission and starts the background listening stream.
    func startListening() {
        guard !isListening else { return }
        
        // macOS standard microphone permission check using AVCaptureDevice
        if #available(macOS 10.14, *) {
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                self.setupAudioAnalysis()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                    if granted {
                        self?.setupAudioAnalysis()
                    } else {
                        print("Microphone access denied for ClapWakeEngine.")
                    }
                }
            case .denied, .restricted:
                print("Microphone access denied or restricted for ClapWakeEngine.")
            @unknown default:
                break
            }
        }
    }
    
    /// Stops the audio engine and releases stream resources for absolute zero battery draw.
    func stopListening() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        streamAnalyzer?.removeAllRequests()
        
        audioEngine = nil
        streamAnalyzer = nil
        isListening = false
        print("ClapWakeEngine suspended.")
    }
    
    // MARK: - Core Audio Analysis
    
    private func setupAudioAnalysis() {
        let engine = AVAudioEngine()
        self.audioEngine = engine
        
        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        
        // Initialize the stream analyzer using the input node's native format
        streamAnalyzer = SNAudioStreamAnalyzer(format: inputFormat)
        
        do {
            // Use Apple's highly optimized, on-device audio classification model (Revision 1)
            let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            
            // Register self as the observer on the background analysis queue
            try streamAnalyzer?.add(request, withObserver: self)
            
            // Install the tap on the audio engine graph.
            // A 8192 buffer size optimizes efficiency limits over aggressive small-buffer polling
            inputNode.installTap(onBus: 0, bufferSize: 8192, format: inputFormat) { [weak self] buffer, time in
                self?.analysisQueue.async {
                    self?.streamAnalyzer?.analyze(buffer, atAudioFramePosition: time.sampleTime)
                }
            }
            
            engine.prepare()
            try engine.start()
            isListening = true
            print("ClapWakeEngine active on Neural Engine. Listening for claps...")
            
        } catch {
            print("Failed to initialize SoundAnalysis request or start engine: \(error.localizedDescription)")
            stopListening()
        }
    }
    
    private var clapCount: Int = 0
    
    // MARK: - Action Trigger
    
    private func registerClap() {
        let now = Date()
        let timeSinceLastClap = now.timeIntervalSince(lastClapTime)
        
        // Block all claps if we are in a 3-second cooldown after a successful sequence
        if timeSinceLastClap < -0.1 { return } // If lastClapTime is in the future (cooldown)
        
        // If it's been more than 1.5 seconds since the last clap, restart the sequence
        if timeSinceLastClap > 1.5 {
            clapCount = 1
            lastClapTime = now
            print("👏 First clap detected (awaiting second...)")
        } 
        // If it's a valid second clap (not an immediate echo, must be > 0.3s gap)
        else if timeSinceLastClap > 0.3 {
            clapCount += 1
            lastClapTime = now
            
            if clapCount == 2 {
                // Double clap achieved! Reset count.
                clapCount = 0
                
                // Set lastClapTime to the future to enforce a 3-second cooldown
                lastClapTime = Date().addingTimeInterval(3.0)
                
                DispatchQueue.main.async {
                    print("👏👏 DOUBLE CLAP DETECTED! Waking Jarvis.")
                    self.onClapDetected?()
                }
            }
        }
    }
}

// MARK: - SNResultsObserving Delegate

extension ClapWakeEngine: SNResultsObserving {
    
    /// Called repeatedly by the SoundAnalysis framework as audio buffers process
    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let classificationResult = result as? SNClassificationResult else { return }
        
        // SNClassificationResult returns an array of label probabilities.
        for classification in classificationResult.classifications {
            if classification.identifier.contains("clapping") || classification.identifier.contains("hands_clap") || classification.identifier == "clapping" {
                
                if classification.confidence > 0.20 {
                    print("🔍 Audio frame analyzed. Clap confidence: \(String(format: "%.2f", classification.confidence * 100))%")
                }
                
                // Requirement: Confidence > 0.65 (macOS echo cancellation makes loud claps hard to detect cleanly)
                if classification.confidence > 0.65 {
                    registerClap()
                    break
                }
            }
        }
    }
    
    func request(_ request: SNRequest, didFailWithError error: Error) {
        print("SoundAnalysis request failed: \(error.localizedDescription)")
    }
    
    func requestDidComplete(_ request: SNRequest) {
        print("SoundAnalysis stream completed.")
    }
}
