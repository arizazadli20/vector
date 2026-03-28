//
//  ArcReactorView.swift
//  Vectormac
//
//  Animated Arc Reactor — Jarvis HUD centerpiece
//

import SwiftUI

struct ArcReactorView: View {
    let isListening: Bool
    
    @State private var rotation1: Double = 0
    @State private var rotation2: Double = 0
    @State private var rotation3: Double = 0
    @State private var coreScale: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            // Ring 4 — outermost
            Circle()
                .stroke(Color.cyan.opacity(0.1), lineWidth: 1)
                .frame(width: 200, height: 200)
                .rotationEffect(.degrees(-rotation3))
            
            // Ring 3 — dotted
            Circle()
                .stroke(Color.cyan.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                .frame(width: 150, height: 150)
                .rotationEffect(.degrees(rotation2))
            
            // Ring 2
            Circle()
                .stroke(Color.cyan.opacity(0.35), lineWidth: 1.5)
                .frame(width: 110, height: 110)
                .rotationEffect(.degrees(-rotation1))
            
            // Ring 1 — dashed inner
            Circle()
                .stroke(Color.cyan.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .frame(width: 70, height: 70)
                .rotationEffect(.degrees(rotation1))
            
            // Spokes
            ForEach(0..<12, id: \.self) { i in
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.cyan.opacity(0.3), .clear],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 1, height: 90)
                    .offset(y: -45)
                    .rotationEffect(.degrees(Double(i) * 30))
            }
            .rotationEffect(.degrees(rotation3 * 0.5))
            
            // Segments
            ForEach(0..<8, id: \.self) { i in
                Triangle()
                    .fill(Color.cyan.opacity(0.12))
                    .frame(width: 16, height: 28)
                    .offset(y: -55)
                    .rotationEffect(.degrees(Double(i) * 45))
            }
            .rotationEffect(.degrees(-rotation2))
            
            // Core glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white, Color.cyan, .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 25
                    )
                )
                .frame(width: 40, height: 40)
                .shadow(color: Color.cyan.opacity(0.5), radius: 30)
                .shadow(color: Color.cyan.opacity(0.2), radius: 60)
                .scaleEffect(coreScale)
        }
        .brightness(isListening ? 0.3 : 0)
        .onAppear {
            withAnimation(.linear(duration: 10).repeatForever(autoreverses: false)) {
                rotation1 = 360
            }
            withAnimation(.linear(duration: 15).repeatForever(autoreverses: false)) {
                rotation2 = 360
            }
            withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
                rotation3 = 360
            }
            withAnimation(.easeInOut(duration: 2).repeatForever()) {
                coreScale = 1.15
            }
        }
    }
}

// Triangle shape for reactor segments
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
