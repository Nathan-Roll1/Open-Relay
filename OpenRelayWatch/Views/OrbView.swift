import SwiftUI

/// A calm animated orb. Listening: swells smoothly with your voice.
/// Thinking: a slow rotating arc. Speaking: soft ripples. Static with
/// Reduce Motion or in Always On.
struct OrbView: View {
    enum Mode { case idle, listening, thinking, speaking }
    let level: Double
    let mode: Mode
    let reduced: Bool

    /// Smoothed mic level so the orb doesn't jitter.
    @State private var smoothed: Double = 0

    var body: some View {
        let schedule = AnimationTimelineSchedule(minimumInterval: 1.0 / 30.0, paused: reduced || mode == .idle)
        TimelineView(schedule) { context in
            orb(at: context.date.timeIntervalSinceReferenceDate)
        }
        .onChange(of: level) { _, new in
            // Fast rise, slower fall.
            smoothed = new > smoothed ? smoothed * 0.4 + new * 0.6 : smoothed * 0.8 + new * 0.2
        }
        .animation(.easeOut(duration: 0.12), value: smoothed)
        .animation(.easeInOut(duration: 0.3), value: mode)
    }

    private func orb(at time: Double) -> some View {
        let breathe: Double = 0.5 + 0.5 * sin(time * 2.2)
        let coreScale = CGFloat(reduced ? 0.82 : scale(t: time, breathe: breathe))
        return ZStack {
            if mode == .speaking && !reduced {
                ForEach(0..<2, id: \.self) { index in
                    ripple(at: time, index: index)
                }
            }
            Circle()
                .fill(RadialGradient(colors: [color.opacity(0.95), color.opacity(0.35)],
                                     center: .center, startRadius: 4, endRadius: 50))
                .scaleEffect(coreScale)
            outline(at: time, breathe: breathe)
        }
    }

    private func ripple(at time: Double, index: Int) -> some View {
        let phase: Double = (time * 0.8 + Double(index) * 0.5).truncatingRemainder(dividingBy: 1)
        return Circle()
            .stroke(color.opacity(0.35 * (1 - phase)), lineWidth: 2)
            .scaleEffect(CGFloat(0.85 + phase * 0.3))
    }

    @ViewBuilder
    private func outline(at time: Double, breathe: Double) -> some View {
        if mode == .thinking && !reduced {
            Circle()
                .trim(from: 0, to: 0.3)
                .stroke(Color.white.opacity(0.6), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(time * 120))
                .scaleEffect(0.95)
        } else {
            Circle()
                .stroke(color.opacity(0.4), lineWidth: 2)
                .scaleEffect(CGFloat(reduced ? 0.9 : 0.95 + breathe * 0.03))
        }
    }

    private func scale(t: Double, breathe: Double) -> Double {
        switch mode {
        case .idle: return 0.82
        case .listening: return 0.84 + min(1, smoothed) * 0.2
        case .thinking: return 0.84 + breathe * 0.04
        case .speaking: return 0.88 + (0.5 + 0.5 * sin(t * 5)) * 0.06
        }
    }

    private var color: Color {
        switch mode {
        case .idle: return .gray
        case .listening: return .cyan
        case .thinking: return .indigo
        case .speaking: return .purple
        }
    }
}
