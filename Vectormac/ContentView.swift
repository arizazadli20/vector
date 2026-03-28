//
//  ContentView.swift
//  Vectormac
//
//  J.A.R.V.I.S. Main HUD
//

import SwiftUI

struct ContentView: View {
    @StateObject private var voiceEngine = VoiceEngine()
    @StateObject private var brain = GroqBrain.shared
    @StateObject private var clapEngine = ClapWakeEngine()
    @State private var showSettings = false
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background
                Color(red: 0.008, green: 0.04, blue: 0.075)
                    .ignoresSafeArea()
                
                // Ambient glow
                RadialGradient(
                    colors: [Color.cyan.opacity(0.06), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: 400
                )
                .ignoresSafeArea()
                
                // Main content
                VStack(spacing: 16) {
                    Spacer()
                    
                    // Title
                    Text("J.A.R.V.I.S.")
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, Color.cyan.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(color: Color.cyan.opacity(0.3), radius: 10)
                    
                    // Arc Reactor (Now functions as the Mic Button!)
                    ArcReactorView(isListening: voiceEngine.isListening)
                        .frame(width: 220, height: 220)
                        .contentShape(Circle())
                        .onTapGesture {
                            voiceEngine.toggleListening()
                        }
                    
                    // Waveform
                    WaveformView(audioLevel: voiceEngine.audioLevel, isListening: voiceEngine.isListening)
                        .frame(maxWidth: 500)
                        .padding(.horizontal, 40)
                    
                    // Status
                    Text(voiceEngine.statusText)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(Color.cyan)
                        .shadow(color: Color.cyan.opacity(0.4), radius: 5)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: 500, height: 20, alignment: .center)
                        .multilineTextAlignment(.center)
                        .animation(nil, value: voiceEngine.statusText)
                        
                    // Transcript area (Inline to prevent overlapping)
                    if !voiceEngine.transcript.isEmpty {
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(spacing: 8) {
                                    ForEach(Array(voiceEngine.transcript.enumerated()), id: \.offset) { index, line in
                                        HStack {
                                            if line.role == "user" { Spacer() }
                                            
                                            Text(line.role == "jarvis" ? "JARVIS: \(line.text)" : line.text)
                                                .font(.system(size: 13, design: .monospaced))
                                                .padding(10)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .fill(Color.cyan.opacity(line.role == "user" ? 0.1 : 0.04))
                                                        .overlay(
                                                            RoundedRectangle(cornerRadius: 8)
                                                                .stroke(Color.cyan.opacity(line.role == "user" ? 0.2 : 0.08), lineWidth: 1)
                                                        )
                                                )
                                                .foregroundColor(line.role == "jarvis" ? .cyan : Color(red: 0.78, green: 0.94, blue: 1.0))
                                                .multilineTextAlignment(line.role == "user" ? .trailing : .leading)
                                            
                                            if line.role == "jarvis" { Spacer() }
                                        }
                                        .id(index)
                                        .animation(nil, value: line.text)
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                            .frame(maxWidth: 600)
                            .frame(height: 120) // Fixed height block so it doesn't push the UI too much
                            .onChange(of: voiceEngine.transcript.count) { _, _ in
                                proxy.scrollTo(voiceEngine.transcript.count - 1, anchor: .bottom)
                            }
                        }
                    }
                    else {
                        // Empty placeholder so the UI doesn't jump drastically when the first word comes in
                        Spacer().frame(height: 120)
                    }
                    
                    Spacer()
                }
                
                // Settings gear
                VStack {
                    HStack {
                        Spacer()
                        Button(action: { showSettings = true }) {
                            Image(systemName: "gearshape")
                                .font(.title3)
                                .foregroundColor(Color.cyan.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                        .padding(20)
                    }
                    Spacer()
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(brain: brain)
        }
        .onAppear {
            clapEngine.onClapDetected = {
                if !voiceEngine.isListening {
                    voiceEngine.toggleListening()
                }
            }
            clapEngine.startListening()
            
            if !brain.hasAPIKey {
                showSettings = true
            }
        }
    }
    
    func currentTime() -> String {
        Date().formatted(date: .omitted, time: .standard)
    }
    
    func currentDate() -> String {
        Date().formatted(date: .abbreviated, time: .omitted)
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var brain: GroqBrain
    @Environment(\.dismiss) var dismiss
    @State private var apiKey = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("N E U R A L   N E T W O R K")
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(.cyan)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("G R O Q   A P I   K E Y")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.cyan.opacity(0.5))
                
                SecureField("gsk_...", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 14, design: .monospaced))
                
                Text("Get your free key at console.groq.com/keys")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Button("ACTIVATE NEURAL LINK") {
                brain.apiKey = apiKey.trimmingCharacters(in: .whitespaces)
                dismiss()
            }
            .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
            .buttonStyle(.borderedProminent)
            .tint(.cyan)
            
            HStack {
                Circle()
                    .fill(brain.hasAPIKey ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(brain.hasAPIKey ? "Neural network connected" : "Neural network offline")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(30)
        .frame(width: 380)
        .onAppear { apiKey = brain.apiKey }
    }
}

// MARK: - HUD Components

#Preview {
    ContentView()
        .frame(width: 900, height: 600)
}
