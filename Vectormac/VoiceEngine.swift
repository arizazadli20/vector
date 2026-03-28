//
//  VoiceEngine.swift
//  Vectormac
//
//  Speech recognition + synthesis — Jarvis's ears and voice
//

import Foundation
import Speech
import AVFoundation
import AppKit

class VoiceEngine: ObservableObject {
    
    @Published var isListening = false
    @Published var isSpeaking = false
    @Published var statusText = "STANDBY"
    @Published var transcript: [(role: String, text: String)] = []
    @Published var currentHearing = ""
    @Published var audioLevel: CGFloat = 0
    
    private var speechSynthesizer: NSSpeechSynthesizer?
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?
    private let brain = GroqBrain.shared
    private let systemUtils = SystemUtils.shared
    
    private var silenceTimer: Timer?
    private var isProcessing = false
    
    init() {
        // Speech recognizer
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        
        // Speech synthesizer with Daniel voice
        let synth = NSSpeechSynthesizer()
        if let synth = synth {
            let danielVoice = NSSpeechSynthesizer.availableVoices.first {
                $0.rawValue.lowercased().contains("daniel")
            }
            if let voice = danielVoice {
                synth.setVoice(voice)
            }
            synth.rate = 200
            self.speechSynthesizer = synth
        }
    }
    
    // MARK: - Speech Synthesis
    
    func speak(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isSpeaking = true
            self.statusText = "SPEAKING"
            self.transcript.append((role: "jarvis", text: text))
            
            guard let synth = self.speechSynthesizer else {
                // Fallback: use macOS 'say' command
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
                process.arguments = ["-v", "Daniel", "-r", "195", text]
                try? process.run()
                
                DispatchQueue.global().async {
                    process.waitUntilExit()
                    DispatchQueue.main.async {
                        self.isSpeaking = false
                        self.isProcessing = false
                        self.statusText = "STANDBY"
                    }
                }
                return
            }
            
            synth.startSpeaking(text)
            
            // Poll for completion on background thread
            DispatchQueue.global(qos: .userInitiated).async {
                while synth.isSpeaking {
                    Thread.sleep(forTimeInterval: 0.1)
                }
                DispatchQueue.main.async {
                    self.isSpeaking = false
                    self.isProcessing = false
                    self.statusText = "STANDBY"
                }
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
    
    // MARK: - Permission Request
    
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
                    self.statusText = "SPEECH NOT DETERMINED"
                @unknown default:
                    self.statusText = "UNKNOWN PERMISSION STATE"
                }
            }
        }
    }
    
    // MARK: - Begin Recognition
    
    private func beginRecognition() {
        // Clean up any previous session
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
        
        // Get input node and format
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // Safety check: format must have channels
        guard recordingFormat.channelCount > 0 else {
            statusText = "NO AUDIO INPUT DEVICE"
            return
        }
        
        // Install audio tap
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            request.append(buffer)
            
            // Calculate audio level
            if let channelData = buffer.floatChannelData?[0] {
                let frames = Int(buffer.frameLength)
                var sum: Float = 0
                for i in 0..<frames { sum += abs(channelData[i]) }
                let avg = sum / Float(max(frames, 1))
                DispatchQueue.main.async {
                    self?.audioLevel = CGFloat(min(avg * 10, 1.0))
                }
            }
        }
        
        // Start recognition task
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                if let result = result {
                    let text = result.bestTranscription.formattedString
                    self.currentHearing = text
                    self.statusText = "HEARING: \(text)"
                    
                    // Reset silence timer
                    self.silenceTimer?.invalidate()
                    self.silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
                        guard let self = self else { return }
                        self.processCommand(text)
                    }
                }
                
                if let error = error {
                    // Only show error if we're still supposed to be listening
                    if self.isListening {
                        print("Recognition error: \(error.localizedDescription)")
                    }
                }
            }
        }
        
        // Start audio engine
        engine.prepare()
        do {
            try engine.start()
            isListening = true
            statusText = "LISTENING"
            currentHearing = ""
        } catch {
            statusText = "AUDIO ERROR: \(error.localizedDescription)"
            cleanupAudioSession()
        }
    }
    
    // MARK: - Stop Listening
    
    func stopListening() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        isListening = false
        audioLevel = 0
        cleanupAudioSession()
        if !isProcessing {
            statusText = "STANDBY"
        }
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
    
    // MARK: - Command Processing
    
    private func processCommand(_ text: String) {
        guard !isProcessing, !text.isEmpty else { return }
        isProcessing = true
        stopListening()
        
        statusText = "PROCESSING"
        transcript.append((role: "user", text: text))
        currentHearing = ""
        
        // Process on background thread to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Check for local commands first
            if let localResponse = self.systemUtils.handleCommand(text) {
                DispatchQueue.main.async {
                    self.statusText = "THINKING"
                }
                Thread.sleep(forTimeInterval: 0.2)
                self.speak(localResponse)
            } else {
                // Fall back to Groq AI
                DispatchQueue.main.async {
                    self.statusText = "THINKING"
                }
                
                // Use semaphore to make async call synchronous on this background thread
                let semaphore = DispatchSemaphore(value: 0)
                var response = "Neural network timeout, sir."
                
                Task {
                    response = await self.brain.ask(text)
                    semaphore.signal()
                }
                
                semaphore.wait()
                self.speak(response)
            }
        }
    }
}
