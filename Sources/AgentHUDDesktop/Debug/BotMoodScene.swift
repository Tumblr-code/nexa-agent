import AgentHUDCore
import SwiftUI

/// Claude's and Codex's bots acting out a phase over time, one frame every `every` seconds: what their moods look
/// like across the acts a phase picks from (snapshots).
struct BotMoodScene: View {
    let phase: BotPhase
    var seconds: TimeInterval = 48
    var every: TimeInterval = 0.8

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(["Claude", "ChatGPT"], id: \.self) { vendor in
                let frames = Self.frames(vendor, phase: phase, seconds: seconds, every: every)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(56), spacing: 4), count: 15), spacing: 4) {
                    ForEach(frames.indices, id: \.self) { index in
                        Image(decorative: frames[index], scale: 2)
                            .frame(width: 56, height: 56)
                            .background(Color(white: 0.05), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
        .padding(16)
        .background(Color(white: 0.10))
    }

    static func frames(_ vendor: String, phase: BotPhase, seconds: TimeInterval, every: TimeInterval) -> [CGImage] {
        guard let form = BotForm.form(for: vendor) else { return [] }
        var motion = BotMotion(seed: 7)
        motion.staysBot = true
        motion.spin = form.spec.spin
        motion.set(phase, at: 0)
        var images: [CGImage] = [], now: TimeInterval = 0, next: TimeInterval = 1
        while now <= seconds {
            motion.step(to: now, aim: CGPoint(x: 0.2, y: 0.3))
            if now >= next, let image = BotRenderer.image(form, motion: motion, side: 40) {
                images.append(image)
                next += every
            }
            now += 1.0 / 30
        }
        return images
    }
}
