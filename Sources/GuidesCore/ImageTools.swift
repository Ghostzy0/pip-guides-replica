import AppKit
import CoreImage

public enum ImageTools {
    public static func size(_ data: Data) throws -> CGSize {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 12_000, height <= 12_000, width * height <= 40_000_000 else { throw GuideError.invalidImage }
        return CGSize(width: width, height: height)
    }
    public static func cgImage(_ data: Data) throws -> CGImage {
        _ = try size(data)
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) else { throw GuideError.invalidImage }
        return image
    }
    public static func png(_ image: CGImage) throws -> Data {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]), data.count <= 16_000_000 else { throw GuideError.invalidImage }
        return data
    }
    public static func normalise(_ data: Data) throws -> Data { try png(cgImage(data)) }
    public static func region(_ unit: CGRect, width: Int, height: Int) throws -> CGRect {
        guard unit.origin.x.isFinite, unit.origin.y.isFinite, unit.width.isFinite, unit.height.isFinite,
              unit.minX >= 0, unit.minY >= 0, unit.maxX <= 1.00001, unit.maxY <= 1.00001,
              unit.width > 0.002, unit.height > 0.002 else { throw GuideError.invalidRegion }
        // Unit rectangles use a top-left origin, like screenshots and the editor.
        return CGRect(x: floor(unit.minX * Double(width)), y: floor(unit.minY * Double(height)),
                      width: ceil(unit.width * Double(width)), height: ceil(unit.height * Double(height))).intersection(CGRect(x: 0, y: 0, width: width, height: height))
    }
    public static func crop(_ data: Data, unit: CGRect) throws -> Data {
        let image = try cgImage(data), rect = try region(unit, width: image.width, height: image.height)
        guard let cropped = image.cropping(to: rect) else { throw GuideError.invalidRegion }
        return try png(cropped)
    }
    public enum Edit { case redact, blur, highlight }
    public static func edit(_ data: Data, unit: CGRect, kind: Edit) throws -> Data {
        let image = try cgImage(data)
        let rect = try region(unit, width: image.width, height: image.height)
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw GuideError.invalidImage }
        let full = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        ctx.draw(image, in: full)
        let flipped = CGRect(x: rect.minX, y: Double(image.height) - rect.maxY, width: rect.width, height: rect.height)
        switch kind {
        case .redact:
            ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fill(flipped)
        case .highlight:
            ctx.setStrokeColor(CGColor(gray: 0, alpha: 1)); ctx.setLineWidth(max(3, Double(image.width) / 300)); ctx.stroke(flipped.insetBy(dx: 2, dy: 2))
        case .blur:
            // Flattened blur, never a CSS overlay. Solid redaction is the confidentiality tool.
            let input = CIImage(cgImage: image)
            let output = input.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 24]).cropped(to: input.extent)
            guard let blurred = CIContext(options: [.useSoftwareRenderer: true]).createCGImage(output, from: input.extent) else { throw GuideError.invalidImage }
            ctx.saveGState(); ctx.clip(to: flipped); ctx.draw(blurred, in: full); ctx.restoreGState()
        }
        guard let result = ctx.makeImage() else { throw GuideError.invalidImage }
        return try png(result)
    }
    public static func marked(_ data: Data, at point: UnitPoint?) throws -> Data {
        guard let point, point.valid else { return data }
        let image = try cgImage(data)
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw GuideError.invalidImage }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let r = max(10, Double(image.width) / 65), x = point.x * Double(image.width), y = (1-point.y) * Double(image.height)
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 1)); ctx.setLineWidth(6); ctx.strokeEllipse(in: CGRect(x: x-r, y: y-r, width: r*2, height: r*2))
        ctx.setStrokeColor(CGColor(gray: 0, alpha: 1)); ctx.setLineWidth(3); ctx.strokeEllipse(in: CGRect(x: x-r, y: y-r, width: r*2, height: r*2))
        guard let result = ctx.makeImage() else { throw GuideError.invalidImage }; return try png(result)
    }
}
