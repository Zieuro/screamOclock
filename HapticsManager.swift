//
//  HapticsManager.swift
//  Scream O Clock
//
//  Created by Tyler Zacharias on 9/7/25.
//


import Foundation
import CoreHaptics
import UIKit
import Combine

final class HapticsManager: ObservableObject {
    private var engine: CHHapticEngine?

    init() { prepare() }

    private func prepare() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            engine = try CHHapticEngine()
            engine?.stoppedHandler = { [weak self] reason in
                // Try to restart if the engine stops (e.g., app went inactive and back)
                try? self?.engine?.start()
            }
            engine?.resetHandler = { [weak self] in
                // Engine reset by the system; recreate resources
                self?.prepare()
                try? self?.engine?.start()
            }
            try engine?.start()
        } catch {
            print("Haptics not available: \(error.localizedDescription)")
        }
    }

    /// 2-second continuous rumble (foreground only)
    func longRumble(duration: TimeInterval = 2.0, intensity: Float = 0.75, sharpness: Float = 0.35) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            // Fallback: stronger notification haptic
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        let i = CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity)
        let s = CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
        let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [i, s], relativeTime: 0, duration: duration)

        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player  = try engine?.makePlayer(with: pattern)
            try engine?.start()
            try player?.start(atTime: 0)
        } catch {
            print("Failed to play long haptic: \(error.localizedDescription)")
        }
    }

    /// Punchy triple-pulse pattern (~0.9s total)
    func triplePulse() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            return
        }
        let baseI: Float = 0.9, baseS: Float = 0.6
        let e1 = CHHapticEvent(eventType: .hapticTransient,
                               parameters: [.init(parameterID: .hapticIntensity, value: baseI),
                                            .init(parameterID: .hapticSharpness, value: baseS)],
                               relativeTime: 0.0)
        let e2 = CHHapticEvent(eventType: .hapticTransient,
                               parameters: [.init(parameterID: .hapticIntensity, value: baseI),
                                            .init(parameterID: .hapticSharpness, value: baseS)],
                               relativeTime: 0.3)
        let e3 = CHHapticEvent(eventType: .hapticTransient,
                               parameters: [.init(parameterID: .hapticIntensity, value: baseI),
                                            .init(parameterID: .hapticSharpness, value: baseS)],
                               relativeTime: 0.6)
        do {
            let pattern = try CHHapticPattern(events: [e1, e2, e3], parameters: [])
            let player  = try engine?.makePlayer(with: pattern)
            try engine?.start()
            try player?.start(atTime: 0)
        } catch {
            print("Failed to play triple pulse: \(error.localizedDescription)")
        }
    }
}
