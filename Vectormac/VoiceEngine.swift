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
    
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?
    private let brain = GroqBrain.shared
    private let systemUtils = SystemUtils.shared
    
    private var silenceTimer: Timer?
    private var maxTimer: Timer?
    private var lastText = ""
    private var isProcessing = false
    
    init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }
    
    // MARK: - Speech (macOS say command)
    
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
        if isListening {
            // If user taps to stop — use whatever was heard so far
            let captured = lastText.trimmingCharacters(in: .whitespaces)
            forceStop()
            if !captured.isEmpty {
                processCommand(captured)
            }
        } else {
            startListeningWithPermission()
        }
    }
    
    // MARK: - Permission + Start
    
    private func startListeningWithPermission() {
        guard !isProcessing else { return }
        
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if status == .authorized {
                    self.beginRecognition()
                } else {
                    self.statusText = "MICROPHONE PERMISSION DENIED"
                }
            }
        }
    }
    
    // MARK: - Core Recognition
    
    private func beginRecognition() {
        forceStop()
        
        guard let recognizer = recognizer, recognizer.isAvailable else {
            statusText = "SPEECH ENGINE NOT AVAILABLE"
            return
        }
        
        let engine = AVAudioEngine()
        self.audioEngine = engine
        
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        self.recognitionRequest = request
        self.lastText = ""
        
        let inputNode = engine.inputNode
        let fmt = inputNode.outputFormat(forBus: 0)
        guard fmt.channelCount > 0 else {
            statusText = "NO MICROPHONE DETECTED"
            return
        }
        
        // Tap audio to feed recognizer + compute level
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            guard let data = buffer.floatChannelData?[0] else { return }
            let frames = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<frames { sum += abs(data[i]) }
            let avg = CGFloat(sum / Float(max(frames, 1))) * 10
            DispatchQueue.main.async { self?.audioLevel = min(avg, 1.0) }
        }
        
        // Recognition callback
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty else { return }
                
                DispatchQueue.main.async {
                    self.currentHearing = text
                    self.statusText = "HEARING: \(text)"
                    self.lastText = text
                    
                    // Cancel previous silence timer and set new one
                    self.silenceTimer?.invalidate()
                    self.silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
                        guard let self = self, self.isListening, !self.isProcessing else { return }
                        // Capture what was heard and process it
                        let final = self.lastText
                        self.forceStop()
                        if !final.isEmpty {
                            self.processCommand(final)
                        }
                    }
                }
            }
        }
        
        engine.prepare()
        do {
            try engine.start()
        } catch {
            statusText = "AUDIO ERROR: \(error.localizedDescription)"
            forceStop()
            return
        }
        
        DispatchQueue.main.async {
            self.isListening = true
            self.statusText = "LISTENING"
            self.currentHearing = ""
            
            // Safety valve: auto-stop after 15 seconds max
            self.maxTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
                guard let self = self, self.isListening else { return }
                let final = self.lastText
                self.forceStop()
                if !final.isEmpty {
                    self.processCommand(final)
                } else {
                    self.statusText = "STANDBY"
                }
            }
        }
    }
    
    // MARK: - Stop completely
    
    private func forceStop() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        maxTimer?.invalidate()
        maxTimer = nil
        isListening = false
        audioLevel = 0
        
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
    }
    
    func stopListening() {
        forceStop()
        if !isProcessing { statusText = "STANDBY" }
    }
    
    // MARK: - Process & Ask Groq
    
    private func processCommand(_ text: String) {
        guard !isProcessing, !text.isEmpty else { return }
        isProcessing = true
        
        DispatchQueue.main.async {
            self.statusText = "PROCESSING..."
            self.transcript.append((role: "user", text: text))
            self.currentHearing = ""
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
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
                do {
                    response = await self.brain.ask(text)
                } catch {}
                semaphore.signal()
            }
            
            semaphore.wait()
            self.speak(response)
        }
    }
}
