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
