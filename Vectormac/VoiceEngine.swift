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
    
    private let synthesizer = AVSpeechSynthesizer()
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?
    private let brain = GroqBrain.shared
    private let systemUtils = SystemUtils.shared
    private var synthDelegate: SpeechDelegate?
    
    private var silenceTimer: Timer?
    private var isProcessing = false
    
    init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        synthDelegate = SpeechDelegate(engine: self)
        synthesizer.delegate = synthDelegate
    }
    
    // MARK: - Speech Synthesis (AVSpeechSynthesizer)
    
    func speak(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isSpeaking = true
            self.statusText = "SPEAKING"
            self.transcript.append((role: "jarvis", text: text))
            
            let utterance = AVSpeechUtterance(string: text)
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
            utterance.pitchMultiplier = 0.9
            utterance.volume = 1.0
            
            // Try to find a British English voice
            let preferredVoices = [
                "Daniel", "com.apple.voice.compact.en-GB.Daniel",
                "com.apple.ttsbundle.Daniel-compact"
            ]
            
            var selectedVoice: AVSpeechSynthesisVoice?
            for voiceName in preferredVoices {
                if let voice = AVSpeechSynthesisVoice(identifier: voiceName) {
                    selectedVoice = voice
                    break
                }
            }
            
            if selectedVoice == nil {
                // Fallback: any en-GB voice
                selectedVoice = AVSpeechSynthesisVoice.speechVoices().first {
                    $0.language == "en-GB"
                }
            }
            
            if selectedVoice == nil {
                // Final fallback: any English voice
                selectedVoice = AVSpeechSynthesisVoice(language: "en-US")
            }
            
            utterance.voice = selectedVoice
            self.synthesizer.speak(utterance)
        }
    }
    
    func didFinishSpeaking() {
        DispatchQueue.main.async { [weak self] in
            self?.isSpeaking = false
            self?.isProcessing = false
            self?.statusText = "STANDBY"
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
            statusText = "NO AUDIO INPUT DEVICE"
            return
        }
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            request.append(buffer)
            
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
        
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                if let result = result {
                    let text = result.bestTranscription.formattedString
                    self.currentHearing = text
                    self.statusText = "HEARING: \(text)"
                    
                    self.silenceTimer?.invalidate()
                    self.silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
                        guard let self = self else { return }
                        self.processCommand(text)
                    }
                }
                
                if let error = error, self.isListening {
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
    
    // MARK: - Command Processing
    
    private func processCommand(_ text: String) {
        guard !isProcessing, !text.isEmpty else { return }
        isProcessing = true
        stopListening()
        
        statusText = "PROCESSING"
        transcript.append((role: "user", text: text))
        currentHearing = ""
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            if let localResponse = self.systemUtils.handleCommand(text) {
                DispatchQueue.main.async { self.statusText = "THINKING" }
                Thread.sleep(forTimeInterval: 0.2)
                self.speak(localResponse)
            } else {
                DispatchQueue.main.async { self.statusText = "THINKING" }
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

// MARK: - AVSpeechSynthesizer Delegate

class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate {
    weak var engine: VoiceEngine?
    
    init(engine: VoiceEngine) {
        self.engine = engine
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        engine?.didFinishSpeaking()
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        engine?.didFinishSpeaking()
    }
}
