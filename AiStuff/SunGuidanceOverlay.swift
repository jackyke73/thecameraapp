import SwiftUI
import CoreLocation

/// Lightweight overlay that helps the user compose with better light.
/// Uses `SunCalculator` (astronomy approximation) + device heading to show where the sun is.
struct SunGuidanceOverlay: View {
    let location: CLLocation?
    let heading: CLHeading?
    let isInterferenceHigh: Bool

    private struct SunGuidance {
        let sunAzimuth: Double
        let elevation: Double
        let relToPhone: Double // -180...180 (sun - heading)
        let isGoldenHour: Bool

        var relString: String {
            let deg = Int(abs(relToPhone).rounded())
            return "\(deg)°"
        }

        var turnDirection: String {
            if relToPhone > 0 { return "right" }
            if relToPhone < 0 { return "left" }
            return "" // already aligned
        }

        /// Human-friendly composition suggestion.
        var recommendation: String {
            // If the sun is below the horizon, just say it.
            if elevation < -2 {
                return "Sun is down"
            }

            // Guidance based on relative bearing.
            let absRel = abs(relToPhone)

            // ~Front light (sun close to camera axis)
            if absRel < 20 {
                return isGoldenHour ? "Golden hour front light" : "Harsh front light"
            }

            // ~Side light
            if absRel >= 20 && absRel <= 70 {
                return isGoldenHour ? "Golden hour side light" : "Side light"
            }

            // ~Back light
            if absRel > 110 {
                return isGoldenHour ? "Golden hour backlight" : "Backlight"
            }

            return "Angle for better light"
        }

        var actionText: String {
            if elevation < -2 {
                return "Try street lights / long exposure"
            }

            let absRel = abs(relToPhone)

            // Encourage side light as a default "looks good" heuristic.
            if absRel >= 20 && absRel <= 70 {
                return "Hold this angle"
            }

            // If sun is in front, tell user to rotate until it becomes side light.
            if absRel < 20 {
                return "Turn \(turnDirection) to get side light"
            }

            // If sun is behind, we can keep it (silhouette/backlight) or rotate slightly.
            if absRel > 110 {
                return "Backlight: tap subject to expose"
            }

            return "Turn \(turnDirection) \(relString)"
        }
    }

    private func normalize180(_ degrees: Double) -> Double {
        var x = (degrees + 180).truncatingRemainder(dividingBy: 360)
        if x < 0 { x += 360 }
        return x - 180
    }

    private func compute() -> SunGuidance? {
        guard let location else { return nil }
        guard let heading else { return nil }
        let sun = SunCalculator.compute(date: Date(), coordinate: location.coordinate)

        // iOS: trueHeading is -1 when invalid.
        let h = heading.trueHeading >= 0 ? heading.trueHeading : heading.magneticHeading
        let rel = normalize180(sun.azimuth - h)

        return SunGuidance(
            sunAzimuth: sun.azimuth,
            elevation: sun.elevation,
            relToPhone: rel,
            isGoldenHour: sun.isGoldenHour
        )
    }

    var body: some View {
        // If we don't have enough signal, render nothing.
        guard let g = compute() else {
            return AnyView(EmptyView())
        }

        // When compass is unreliable, don't pretend we know.
        if isInterferenceHigh {
            return AnyView(
                HStack(spacing: 8) {
                    Image(systemName: "location.north.line")
                    Text("Compass interference")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.45), in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
                .allowsHitTesting(false)
            )
        }

        let arrowRotation = Angle(degrees: g.relToPhone)

        return AnyView(
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.35))
                            .frame(width: 30, height: 30)

                        Image(systemName: "arrow.up")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .rotationEffect(arrowRotation)

                        Image(systemName: "sun.max.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(g.isGoldenHour ? .yellow : .white.opacity(0.85))
                            .offset(y: 10)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(g.recommendation)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)

                            if g.isGoldenHour {
                                Text("GOLDEN")
                                    .font(.system(size: 10, weight: .heavy))
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.yellow, in: Capsule(style: .continuous))
                            }
                        }

                        Text(g.actionText)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.90))
                    }
                }

                // Small debug-ish line (kept subtle) — useful during iteration.
                Text("Sun elev \(Int(g.elevation.rounded()))° · rel \(Int(g.relToPhone.rounded()))°")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.55))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.22), radius: 14, x: 0, y: 6)
            .allowsHitTesting(false)
        )
    }
}
