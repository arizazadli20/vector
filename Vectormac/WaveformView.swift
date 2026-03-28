//
//  WaveformView.swift
//  Vectormac
//
//  Audio waveform visualizer
//

import SwiftUI

struct WaveformView: View {
    let audioLevel: CGFloat
    let isListening: Bool
    
    @State private var phase: CGFloat = 0
    
    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2
            let width = size.width
            
            var path = Path()
            
            let amplitude: CGFloat = isListening ? max(audioLevel * 40, 8) : 8
            let opacity: Double = isListening ? 1.0 : 0.3
            
            for x in stride(from: 0, through: width, by: 1) {
                let relativeX = x / width
                let y = midY
                    + sin(relativeX * 4 * .pi + phase * 2) * amplitude
                    + sin(relativeX * 8 * .pi + phase * 3) * (amplitude * 0.3)
                
                if x == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            
            context.stroke(
                path,
                with: .color(Color.cyan.opacity(opacity)),
                lineWidth: isListening ? 2.5 : 1.5
            )
            
            // Glow effect — draw again slightly thicker and transparent
            context.stroke(
                path,
                with: .color(Color.cyan.opacity(opacity * 0.3)),
                lineWidth: isListening ? 6 : 3
            )
        }
        .frame(height: 80)
        .onAppear {
            withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }
}
