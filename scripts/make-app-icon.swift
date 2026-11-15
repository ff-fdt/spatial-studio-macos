import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                                      bytesPerRow: pixels * 4, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            fatalError("Unable to create icon bitmap")
        }
        let proportion = CGFloat(pixels) / 1024
        context.scaleBy(x: proportion, y: proportion)
        context.setAllowsAntialiasing(true)

        let tile = CGPath(roundedRect: CGRect(x: 68, y: 68, width: 888, height: 888),
                          cornerWidth: 195, cornerHeight: 195, transform: nil)
        context.setFillColor(gray: 0, alpha: 1)
        context.addPath(tile)
        context.fillPath()

        // Saturn, drawn on an integer pixel grid. The dark tile stays neutral.
        context.setAllowsAntialiasing(false)
        let grid = min(32, pixels)
        let cell = 1024.0 / Double(grid)
        let colors: [(Double, Double, Double)] = [
            (0.85, 0.64, 0.40), (0.95, 0.79, 0.54), (0.99, 0.88, 0.65),
            (0.83, 0.64, 0.43), (0.96, 0.83, 0.58), (0.99, 0.90, 0.68)
        ]
        let bandLimits = [-0.67, -0.42, -0.14, 0.18, 0.53]
        for row in 0..<grid {
            for col in 0..<grid {
                let x = ((Double(col) + 0.5) / Double(grid) - 0.5) / 0.258
                let y = ((Double(row) + 0.5) / Double(grid) - 0.5) / 0.258
                let disk = x * x + pow(y / 0.93, 2)
                let u = 0.96 * x + 0.28 * y
                let v = -0.28 * x + 0.96 * y
                let ring = pow(u / 1.60, 2) + pow(v / 0.51, 2)
                let ringVisible = ring <= 1 && ring >= 0.40 && (disk > 1 || v < 0)
                let rgb: (Double, Double, Double)
                if ringVisible {
                    if ring > 0.75 && ring < 0.82 && grid == 32 {
                        rgb = (0.47, 0.33, 0.24)
                    } else if v < 0 {
                        rgb = (1.0, 0.86, 0.61)
                    } else {
                        rgb = (0.68, 0.49, 0.33)
                    }
                } else if disk <= 1 {
                    let latitude = v + 0.04 * u * u
                    let (r, g, b) = colors[bandLimits.firstIndex { latitude < $0 } ?? bandLimits.count]
                    let light = -0.46 * x + 0.38 * y + 0.80 * sqrt(1 - disk)
                    let shade = light > 0.70 ? 1.0 : light > 0.40 ? 0.87 : light > 0.08 ? 0.72 : 0.55
                    rgb = (r * shade, g * shade, b * shade)
                } else {
                    continue
                }
                context.setFillColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
                context.fill(CGRect(x: Double(col) * cell, y: Double(row) * cell, width: cell, height: cell))
            }
        }

        let filename = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        let url = output.appendingPathComponent(filename)
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            fatalError("Unable to encode icon")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { fatalError("Unable to save \(filename)") }
    }
}
