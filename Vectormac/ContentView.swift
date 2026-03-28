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
    @State private var showSettings = false
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background
                Color(red: 0.008, green: 0.04, blue: 0.075)
                    .ignoresSafeArea()
                
                // Grid overlay
                GridOverlay()
                
                // Ambient glow
                RadialGradient(
                    colors: [Color.cyan.opacity(0.06), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: 400
                )
                .ignoresSafeArea()
                
                // HUD Panels (using overlay alignment)
                VStack {
                    HStack {
                        HudPanel(label: "SYSTEM TIME", value: currentTime())
                            .padding(20)
                        Spacer()
                        HudPanel(label: "DATE", value: currentDate())
                            .padding(20)
                    }
                    Spacer()
                    HStack {
                        StatusPanel()
                            .padding(20)
                        Spacer()
                        HudPanel(label: "J.A.R.V.I.S.", value: "v3.7.1")
                            .padding(20)
                    }
                }
                
                // Corner decorations
                VStack {
                    HStack {
                        CornerMark()
                        Spacer()
                        CornerMark().rotationEffect(.degrees(90))
                    }
                    Spacer()
                    HStack {
                        CornerMark().rotationEffect(.degrees(270))
                        Spacer()
                        CornerMark().rotationEffect(.degrees(180))
                    }
                }
                .padding(10)
                
                // Main content
                VStack(spacing: 16) {
                    Spacer()
                    
                    // Title
                    Text("J.A.R.V.I.S.")
                        .font(.custom("Courier", size: 28))
                        .fontWeight(.bold)
                        .tracking(8)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, Color.cyan.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(color: Color.cyan.opacity(0.3), radius: 10)
                    
                    // Arc Reactor
                    ArcReactorView(isListening: voiceEngine.isListening)
                        .frame(width: 220, height: 220)
                    
                    // Waveform
                    WaveformView(audioLevel: voiceEngine.audioLevel, isListening: voiceEngine.isListening)
                        .frame(maxWidth: 500)
                        .padding(.horizontal, 40)
                    
                    // Status
                    Text(voiceEngine.statusText)
                        .font(.custom("Courier", size: 13))
                        .fontWeight(.medium)
                        .tracking(4)
                        .foregroundColor(Color.cyan)
                        .shadow(color: Color.cyan.opacity(0.4), radius: 5)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: 500, height: 20, alignment: .leading)
                        .multilineTextAlignment(.leading)
                        .animation(nil, value: voiceEngine.statusText)
                    
                    // Voice Button
                    Button(action: { voiceEngine.toggleListening() }) {
                        ZStack {
                            Circle()
                                .stroke(
                                    voiceEngine.isListening ? Color.green : Color.cyan,
                                    lineWidth: 2
                                )
                                .frame(width: 60, height: 60)
                                .shadow(color: (voiceEngine.isListening ? Color.green : Color.cyan).opacity(0.3), radius: 10)
                            
                            Image(systemName: voiceEngine.isListening ? "mic.fill" : "mic")
                                .font(.title2)
                                .foregroundColor(voiceEngine.isListening ? .green : .cyan)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                    
                    Spacer()
                }
                
                // Transcript area
                if !voiceEngine.transcript.isEmpty {
                    VStack {
                        Spacer()
                        
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(spacing: 8) {
                                    ForEach(Array(voiceEngine.transcript.enumerated()), id: \.offset) { index, line in
                                        HStack {
                                            if line.role == "user" { Spacer() }
                                            
                                            Text(line.role == "jarvis" ? "JARVIS: \(line.text)" : line.text)
                                                .font(.custom("Courier", size: 13))
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
                                            
                                            if line.role == "jarvis" { Spacer() }
                                        }
                                        .id(index)
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                            .frame(maxWidth: 600, maxHeight: 180)
                            .onChange(of: voiceEngine.transcript.count) { _, _ in
                                withAnimation {
                                    proxy.scrollTo(voiceEngine.transcript.count - 1, anchor: .bottom)
                                }
                            }
                        }
                        .padding(.bottom, 30)
                    }
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
            Text("NEURAL NETWORK CONFIG")
                .font(.custom("Courier", size: 14))
                .fontWeight(.medium)
                .tracking(3)
                .foregroundColor(.cyan)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("GROQ API KEY")
                    .font(.custom("Courier", size: 10))
                    .fontWeight(.medium)
                    .tracking(2)
                    .foregroundColor(.cyan.opacity(0.5))
                
                SecureField("gsk_...", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.custom("Courier", size: 14))
                
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

struct GridOverlay: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 40
            for x in stride(from: 0, through: size.width, by: spacing) {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(Color.cyan.opacity(0.03)), lineWidth: 1)
            }
            for y in stride(from: 0, through: size.height, by: spacing) {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(Color.cyan.opacity(0.03)), lineWidth: 1)
            }
        }
        .ignoresSafeArea()
    }
}

struct CornerMark: View {
    var body: some View {
        ZStack {
            Rectangle().fill(Color.cyan.opacity(0.3)).frame(width: 20, height: 1).offset(x: 10)
            Rectangle().fill(Color.cyan.opacity(0.3)).frame(width: 1, height: 20).offset(y: 10)
        }
    }
}

struct StatusPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SYSTEM STATUS")
                .font(.custom("Courier", size: 9))
                .fontWeight(.medium)
                .tracking(2)
                .foregroundColor(.cyan.opacity(0.4))
            HStack(spacing: 6) {
                Circle().fill(Color.green).frame(width: 6, height: 6)
                    .shadow(color: .green.opacity(0.5), radius: 4)
                Text("All Systems Online")
                    .font(.custom("Courier", size: 13))
                    .foregroundColor(.green)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.cyan.opacity(0.03))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cyan.opacity(0.1), lineWidth: 1))
        )
    }
}

struct HudPanel: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.custom("Courier", size: 9))
                .fontWeight(.medium)
                .tracking(2)
                .foregroundColor(.cyan.opacity(0.4))
            Text(value)
                .font(.custom("Courier", size: 14))
                .monospacedDigit()
                .foregroundColor(Color(red: 0.78, green: 0.94, blue: 1.0))
                .animation(nil, value: value)
        }
        .padding(14)
        .frame(minWidth: 140, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.cyan.opacity(0.03))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cyan.opacity(0.1), lineWidth: 1))
        )
        .fixedSize()
    }
}

#Preview {
    ContentView()
        .frame(width: 900, height: 600)
}
