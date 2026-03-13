import UIKit
import SwiftUI
import RealityKit

// MARK: - Camera Color Mode
enum CameraColorMode: String, CaseIterable {
    case sequence = "Sequence"   // palette cycles per stroke
    case random   = "Random"     // each point gets random palette color
    case driven   = "Driven"     // amplitude/tilt index into palette
}

// MARK: - CameraColorSampler
/// Samples N colors from a circular region of an ARView frame.
class CameraColorSampler {

    /// Sample `count` colors from `image` within a circle defined by
    /// `center` (0–1 normalized) and `radius` (0–1 normalized).
    /// Deduplicates by HSB distance so the palette stays varied.
    static func sample(from image: UIImage,
                       center: CGPoint,
                       radius: CGFloat,
                       count: Int = 24) -> [Color] {

        guard let cgImage = image.cgImage else { return [] }
        let w = CGFloat(cgImage.width)
        let h = CGFloat(cgImage.height)

        // Convert to pixel space
        let cx = center.x * w
        let cy = center.y * h
        let rx = radius * w
        let ry = radius * h

        guard let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return [] }

        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let bytesPerRow   = cgImage.bytesPerRow

        // Sample random points inside the ellipse
        var raw: [(h: CGFloat, s: CGFloat, b: CGFloat)] = []
        var attempts = 0
        while raw.count < count * 3 && attempts < count * 20 {
            attempts += 1
            let angle  = CGFloat.random(in: 0..<2 * .pi)
            let dist   = sqrt(CGFloat.random(in: 0...1))   // uniform disk
            let px = Int(cx + rx * dist * cos(angle))
            let py = Int(cy + ry * dist * sin(angle))

            guard px >= 0, px < Int(w), py >= 0, py < Int(h) else { continue }

            let offset = py * bytesPerRow + px * bytesPerPixel
            let r = CGFloat(bytes[offset])     / 255
            let g = CGFloat(bytes[offset + 1]) / 255
            let b = CGFloat(bytes[offset + 2]) / 255

            var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, a: CGFloat = 0
            UIColor(red: r, green: g, blue: b, alpha: 1).getHue(&hue, saturation: &sat,
                                                                  brightness: &bri, alpha: &a)
            // Skip very dark / very desaturated samples (walls, shadows)
            guard bri > 0.15, sat > 0.05 else { continue }
            raw.append((hue, sat, bri))
        }

        // Deduplicate: keep colors far enough apart in hue space
        let minHueDist: CGFloat = 0.04
        var kept: [(h: CGFloat, s: CGFloat, b: CGFloat)] = []
        for candidate in raw {
            let tooClose = kept.contains { abs($0.h - candidate.h) < minHueDist }
            if !tooClose { kept.append(candidate) }
            if kept.count >= count { break }
        }

        // Fallback: if we got very few, include low-saturation ones too
        if kept.count < 4 {
            kept = raw.prefix(count).map { $0 }
        }

        return kept.map { Color(hue: $0.h, saturation: $0.s, brightness: $0.b) }
    }
}
