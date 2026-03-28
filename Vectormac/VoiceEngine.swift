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
import Combine

@MainActor
class VoiceEngine: ObservableObject {
    
    @Published var isListening = false
    @Published var isSpeaking = false
    @Published var statusText = "STANDBY"
    @Published var transcript: [(role: String, text: String)] = []
    @Published var currentHearing = ""
    @Published var audioLevel: CGFloat = 0
    
    private let speechSynthesizer = NSSpeechSynthesizer()
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private let brain = GroqBrain.shared
    private let systemUtils = SystemUtils.shared
    
    private var silenceTimer: Timer?
    private var lastTranscript = ""
    private var isProcessing = false
    
    init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        
        // Use Daniel voice (British)
        if let daniel = NSSpeechSynthesizer.availableVoices.first(where: {
            $0.rawValue.lowercased().contains("daniel")
        }) {
            speechSynthesizer.setVoice(daniel)
        }
        speechSynthesizer.rate = 195.0 / 300.0 // Approximate from Python rate
    }
    
    // MARK: - Speech Synthesis
    
    func speak(_ text: String) {
        isSpeaking = true
        statusText = "SPEAKING"
        transcript.append((role: "jarvis", text: text))
        
        speechSynthesizer.startSpeaking(text)
        
        // Poll for completion
        Task {
            while speechSynthesizer.isSpeaking {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            isSpeaking = false
            isProcessing = false
            statusText = "STANDBY"
        }
    }
    
    // MARK: - Speech Recognition
    
    func toggleListening() {
        if isListening {
            stopListening()
        } else {
            startListening()
        }
    }
    
    func startListening() {
        guard !isProcessing else { return }
        
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard status == .authorized else {
                    self?.statusText = "MIC PERMISSION DENIED"
                    return
                }
                self?.beginRecognition()
            }
        }
    }
    
    private func beginRecognition() {
        // Cancel any existing task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest, let recognizer = recognizer else { return }
        
        request.shouldReportPartialResults = true
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            
            // Calculate audio level for waveform
            let channelData = buffer.floatChannelData?[0]
            let frames = buffer.frameLength
            if let data = channelData {
                var sum: Float = 0
                for i in 0..<Int(frames) {
                    sum += abs(data[i])
                }
                let avg = sum / Float(frames)
                DispatchQueue.main.async {
                    self?.audioLevel = CGFloat(min(avg * 10, 1.0))
                }
            }
        }
        
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if let result = result {
                    let text = result.bestTranscription.formattedString
                    self.currentHearing = text
                    self.statusText = "HEARING: \(text)"
                    self.lastTranscript = text
                    
                    // Reset silence timer
                    self.silenceTimer?.invalidate()
                    self.silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
                        Task { @MainActor in
                            self.processCommand(text)
                        }
                    }
                }
                
                if error != nil || (result?.isFinal ?? false) {
                    // Don't stop if we're still waiting for silence timer
                }
            }
        }
        
        audioEngine.prepare()
        do {
            try audioEngine.start()
            isListening = true
            statusText = "LISTENING"
            currentHearing = ""
        } catch {
            statusText = "AUDIO ENGINE ERROR"
        }
    }
    
    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isListening = false
        silenceTimer?.invalidate()
        audioLevel = 0
        if !isProcessing {
            statusText = "STANDBY"
        }
    }
    
    // MARK: - Command Processing
    
    private func processCommand(_ text: String) {
        guard !isProcessing, !text.isEmpty else { return }
        isProcessing = true
        stopListening()
        
        statusText = "PROCESSING"
        transcript.append((role: "user", text: text))
        currentHearing = ""
        
        Task {
            // Check for local commands first (from Python vector_brain)
            if let localResponse = systemUtils.handleCommand(text) {
                statusText = "THINKING"
                try? await Task.sleep(nanoseconds: 200_000_000)
                speak(localResponse)
            } else {
                // Fall back to Groq AI
                statusText = "THINKING"
                let response = await brain.ask(text)
                speak(response)
            }
        }
    }
}
