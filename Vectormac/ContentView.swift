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
            
            // Corner decorations
            CornerDecorations()
            
            // HUD Panels
            HudPanels()
            
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
                    .tracking(4)
                    .foregroundColor(Color.cyan)
                    .shadow(color: Color.cyan.opacity(0.4), radius: 5)
                    .animation(.easeInOut(duration: 0.3), value: voiceEngine.statusText)
                
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
        .sheet(isPresented: $showSettings) {
            SettingsView(brain: brain)
        }
        .onAppear {
            if !brain.hasAPIKey {
                showSettings = true
            }
        }
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
                .tracking(3)
                .foregroundColor(.cyan)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("GROQ API KEY")
                    .font(.custom("Courier", size: 10))
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

struct CornerDecorations: View {
    var body: some View {
        ZStack {
            CornerMark().position(x: 25, y: 25)
            CornerMark().rotationEffect(.degrees(90)).position(x: 25, y: UIProxy.height - 25)
            CornerMark().rotationEffect(.degrees(270)).position(x: UIProxy.width - 25, y: 25)
            CornerMark().rotationEffect(.degrees(180)).position(x: UIProxy.width - 25, y: UIProxy.height - 25)
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

enum UIProxy {
    static var width: CGFloat { NSScreen.main?.frame.width ?? 1200 }
    static var height: CGFloat { NSScreen.main?.frame.height ?? 800 }
}

struct HudPanels: View {
    @State private var time = Date()
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            // Top left — time
            HudPanel(label: "SYSTEM TIME", value: time.formatted(date: .omitted, time: .standard))
                .position(x: 120, y: 50)
            
            // Top right — date
            HudPanel(label: "DATE", value: time.formatted(date: .abbreviated, time: .omitted))
                .position(x: UIProxy.width - 150, y: 50)
            
            // Bottom left — status
            VStack(alignment: .leading, spacing: 4) {
                Text("SYSTEM STATUS")
                    .font(.custom("Courier", size: 9))
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
            .position(x: 140, y: UIProxy.height - 60)
            
            // Bottom right — version
            HudPanel(label: "J.A.R.V.I.S.", value: "v3.7.1")
                .position(x: UIProxy.width - 120, y: UIProxy.height - 60)
        }
        .onReceive(timer) { time = $0 }
    }
}

struct HudPanel: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.custom("Courier", size: 9))
                .tracking(2)
                .foregroundColor(.cyan.opacity(0.4))
            Text(value)
                .font(.custom("Courier", size: 14))
                .foregroundColor(Color(red: 0.78, green: 0.94, blue: 1.0))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.cyan.opacity(0.03))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cyan.opacity(0.1), lineWidth: 1))
        )
    }
}

#Preview {
    ContentView()
        .frame(width: 900, height: 600)
}
