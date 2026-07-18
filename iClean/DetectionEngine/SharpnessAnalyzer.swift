import UIKit
import CoreGraphics
import Accelerate

/// Measures how sharp an image is, using **Laplacian variance** — the standard, cheap,
/// on-device technique for this.
///
/// How it works: convert to greyscale, run a Laplacian (edge-detection) kernel, then take
/// the variance of the result. Sharp images have strong edges and therefore high variance;
/// blurry images have weak edges and low variance.
///
/// **Scored per tile, not per image.** Averaging over the whole frame punishes photos that
/// are *meant* to have blur in most of the frame — a Portrait-mode shot, a macro, anything
/// with a shallow depth of field — and also punishes photos with large plain areas like sky.
/// Instead the image is divided into tiles, each is scored, and we take a high percentile.
/// The question becomes "is *any meaningful part* of this photo in focus?", which is what
/// actually distinguishes an artistic shot from a camera-shake mistake.
///
/// Measured on a real photo (sharp vs blurred at full resolution, then scored):
///
///     case                          whole-image   tiled p90
///     sharp                              404         718
///     blurred (radius 8)                   8          12
///     blurred (radius 16)                  2           3
///     portrait, subject 50% of frame     194         495
///     portrait, subject 25% of frame      97         116
///
/// Tiling barely changes genuinely blurry photos but lifts sharp and portrait-style photos
/// well clear of the threshold.
enum SharpnessAnalyzer {

    /// Sharpness score for an image. Higher = sharper. `nil` if the image can't be read.
    ///
    /// Deliberately runs on a downscaled copy — see `DetectionThresholds.blurAnalysisDimension`
    /// for why that dimension was chosen.
    static func sharpnessScore(of image: UIImage,
                               maxDimension: Int = DetectionThresholds.blurAnalysisDimension) -> Float? {
        guard let cgImage = image.cgImage else { return nil }

        let (width, height) = scaledSize(width: cgImage.width,
                                         height: cgImage.height,
                                         maxDimension: maxDimension)
        // Need at least a 1px border for the 3×3 kernel.
        guard width > 2, height > 2,
              let grey = greyscaleBytes(from: cgImage, width: width, height: height) else {
            return nil
        }

        // Convert to Float once so the convolution keeps negative values (an 8-bit
        // convolution would clamp them to zero and skew the variance).
        var pixels = [Float](repeating: 0, count: width * height)
        vDSP_vfltu8(grey, 1, &pixels, 1, vDSP_Length(width * height))

        let fieldWidth = width - 2
        let fieldHeight = height - 2
        var laplacian = [Float](repeating: 0, count: fieldWidth * fieldHeight)
        pixels.withUnsafeBufferPointer { source in
            laplacian.withUnsafeMutableBufferPointer { output in
                for y in 0..<fieldHeight {
                    for x in 0..<fieldWidth {
                        let centre = (y + 1) * width + (x + 1)
                        // 3×3 Laplacian:  0 1 0 / 1 -4 1 / 0 1 0
                        output[y * fieldWidth + x] = source[centre - width]
                            + source[centre + width]
                            + source[centre - 1]
                            + source[centre + 1]
                            - 4 * source[centre]
                    }
                }
            }
        }

        return percentileOfTiles(laplacian, width: fieldWidth, height: fieldHeight)
    }

    // MARK: Tiling

    /// Variance of each tile, then a high percentile across them — "how sharp is the
    /// sharpest meaningful region?". A percentile rather than the outright maximum, so a
    /// single noisy or high-contrast speck can't rescue a genuinely blurry photo.
    private static func percentileOfTiles(_ field: [Float], width: Int, height: Int) -> Float? {
        let tileSize = DetectionThresholds.blurTileSize
        var tileScores: [Float] = []

        field.withUnsafeBufferPointer { values in
            var tileY = 0
            while tileY < height {
                let yEnd = min(tileY + tileSize, height)
                var tileX = 0
                while tileX < width {
                    let xEnd = min(tileX + tileSize, width)
                    // Skip slivers at the right/bottom edge — too small to judge.
                    if (xEnd - tileX) >= tileSize / 2 && (yEnd - tileY) >= tileSize / 2 {
                        var sum: Float = 0
                        var sumOfSquares: Float = 0
                        var count: Float = 0
                        for y in tileY..<yEnd {
                            let row = y * width
                            for x in tileX..<xEnd {
                                let value = values[row + x]
                                sum += value
                                sumOfSquares += value * value
                                count += 1
                            }
                        }
                        if count > 1 {
                            let mean = sum / count
                            tileScores.append((sumOfSquares / count) - (mean * mean))
                        }
                    }
                    tileX += tileSize
                }
                tileY += tileSize
            }
        }

        guard !tileScores.isEmpty else { return nil }
        tileScores.sort()
        let position = Double(tileScores.count - 1) * DetectionThresholds.blurTilePercentile
        return tileScores[min(tileScores.count - 1, max(0, Int(position)))]
    }

    // MARK: Helpers

    /// Aspect-preserving size with the longest side capped at `maxDimension`.
    private static func scaledSize(width: Int, height: Int, maxDimension: Int) -> (Int, Int) {
        let longest = max(width, height)
        guard longest > maxDimension else { return (width, height) }
        let ratio = Double(maxDimension) / Double(longest)
        return (max(Int(Double(width) * ratio), 1), max(Int(Double(height) * ratio), 1))
    }

    /// Draws the image into a tightly-packed 8-bit greyscale buffer (one byte per pixel).
    private static func greyscaleBytes(from cgImage: CGImage, width: Int, height: Int) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: width * height)
        let success = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress,
                                          width: width,
                                          height: height,
                                          bitsPerComponent: 8,
                                          bytesPerRow: width,   // packed: no row padding
                                          space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
                return false
            }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return success ? bytes : nil
    }
}
