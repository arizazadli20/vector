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
    private var isProcessing = false
    private var speakProcess: Process?
    
    init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }
    
    // MARK: - Speech using macOS 'say' command (most reliable)
    
    func speak(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isSpeaking = true
            self.statusText = "SPEAKING"
            self.transcript.append((role: "jarvis", text: text))
        }
        
        // Use macOS 'say' command — same as Python version, 100% reliable
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            process.arguments = ["-v", "Daniel", "-r", "195", text]
            self.speakProcess = process
            
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                print("Say command error: \(error)")
            }
            
            DispatchQueue.main.async {
                self.isSpeaking = false
                self.isProcessing = false
                self.statusText = "STANDBY"
                self.speakProcess = nil
            }
        }
    }
    
    // MARK: - Toggle
    
    func toggleListening() {
        if isListening {
            stopListening()
        } else {
            requestPermissionAndStart()
        }
    }
    
    // MARK: - Permission
    
    private func requestPermissionAndStart() {
        guard !isProcessing else { return }
        
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                switch status {
                case .authorized:
                    self.beginRecognition()
                case .denied, .restricted:
                    self.statusText = "SPEECH PERMISSION DENIED"
                case .notDetermined:
                    self.statusText = "WAITING FOR PERMISSION"
                @unknown default:
                    self.statusText = "UNKNOWN STATE"
                }
            }
        }
    }
    
    // MARK: - Recognition
    
    private func beginRecognition() {
        cleanupAudioSession()
        
        guard let recognizer = recognizer, recognizer.isAvailable else {
            statusText = "SPEECH NOT AVAILABLE"
            return
        }
        
        let engine = AVAudioEngine()
        self.audioEngine = engine
        
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.recognitionRequest = request
        
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        guard recordingFormat.channelCount > 0 else {
            statusText = "NO MICROPHONE"
            return
        }
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            request.append(buffer)
            
            if let data = buffer.floatChannelData?[0] {
                let frames = Int(buffer.frameLength)
                var sum: Float = 0
                for i in 0..<frames { sum += abs(data[i]) }
                let avg = sum / Float(max(frames, 1))
                DispatchQueue.main.async {
                    self?.audioLevel = CGFloat(min(avg * 10, 1.0))
                }
            }
        }
        
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self = self, self.isListening else { return }
                
                if let result = result {
                    let text = result.bestTranscription.formattedString
                    self.currentHearing = text
                    self.statusText = "HEARING: \(text)"
                    
                    self.silenceTimer?.invalidate()
                    self.silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
                        guard let self = self, !self.isProcessing else { return }
                        self.processCommand(text)
                    }
                }
                
                if let error = error {
                    print("Recognition error: \(error.localizedDescription)")
                }
            }
        }
        
        engine.prepare()
        do {
            try engine.start()
            isListening = true
            statusText = "LISTENING"
            currentHearing = ""
        } catch {
            statusText = "AUDIO ERROR"
            cleanupAudioSession()
        }
    }
    
    // MARK: - Stop
    
    func stopListening() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        isListening = false
        audioLevel = 0
        cleanupAudioSession()
        if !isProcessing { statusText = "STANDBY" }
    }
    
    private func cleanupAudioSession() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
    }
    
    // MARK: - Process Command
    
    private func processCommand(_ text: String) {
        guard !isProcessing, !text.isEmpty else { return }
        isProcessing = true
        stopListening()
        
        statusText = "PROCESSING"
        transcript.append((role: "user", text: text))
        currentHearing = ""
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Check local commands first
            if let localResponse = self.systemUtils.handleCommand(text) {
                DispatchQueue.main.async { self.statusText = "THINKING" }
                Thread.sleep(forTimeInterval: 0.3)
                self.speak(localResponse)
                return
            }
            
            // Groq AI
            DispatchQueue.main.async { self.statusText = "THINKING" }
            
            let semaphore = DispatchSemaphore(value: 0)
            var response = "Neural network timeout, sir."
            
            Task {
                response = await self.brain.ask(text)
                semaphore.signal()
            }
            
            let result = semaphore.wait(timeout: .now() + 30)
            if result == .timedOut {
                response = "The neural network took too long, sir. Please try again."
            }
            
            self.speak(response)
        }
    }
}
