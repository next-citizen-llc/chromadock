import CoreGraphics
import Foundation

enum WallpaperSampler {
    /// Where `image` sits when aspect-filled onto `canvas` (origin bottom-left).
    static func aspectFillFrame(imageSize: CGSize, canvas: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, canvas.width > 0, canvas.height > 0 else {
            return .zero
        }
        let scale = max(canvas.width / imageSize.width, canvas.height / imageSize.height)
        let w = imageSize.width * scale
        let h = imageSize.height * scale
        return CGRect(
            x: (canvas.width - w) / 2,
            y: (canvas.height - h) / 2,
            width: w,
            height: h
        )
    }

    /// Mean Rec. 709 luminance of `image` in `sampleInScreen` (screen-local,
    /// origin bottom-left, same space as `screenSize`).
    static func meanLuminance(
        of image: CGImage,
        screenSize: CGSize,
        sampleInScreen: CGRect
    ) -> Double? {
        let imageSize = CGSize(width: image.width, height: image.height)
        let drawn = aspectFillFrame(imageSize: imageSize, canvas: screenSize)
        let hit = sampleInScreen.intersection(drawn)
        guard !hit.isNull, hit.width > 0.5, hit.height > 0.5 else { return nil }

        let scaleX = imageSize.width / drawn.width
        let scaleY = imageSize.height / drawn.height
        let imgX = (hit.minX - drawn.minX) * scaleX
        let imgMaxX = (hit.maxX - drawn.minX) * scaleX
        let imgYBottom = (hit.minY - drawn.minY) * scaleY
        let imgYTop = (hit.maxY - drawn.minY) * scaleY
        let cgY = imageSize.height - imgYTop
        let cgH = max(imgYTop - imgYBottom, 1)
        let crop = CGRect(
            x: imgX,
            y: cgY,
            width: max(imgMaxX - imgX, 1),
            height: cgH
        ).integral
        let bounds = CGRect(x: 0, y: 0, width: imageSize.width, height: imageSize.height)
        let clamped = crop.intersection(bounds)
        guard !clamped.isNull, clamped.width >= 1, clamped.height >= 1,
              let cropped = image.cropping(to: clamped)
        else { return nil }

        let outW = 16
        let outH = 8
        guard let ctx = CGContext(
            data: nil,
            width: outW,
            height: outH,
            bitsPerComponent: 8,
            bytesPerRow: outW * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .low
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: outW, height: outH))
        guard let data = ctx.data else { return nil }
        let ptr = data.bindMemory(to: UInt8.self, capacity: outW * outH * 4)
        var sum = 0.0
        let count = outW * outH
        for i in 0..<count {
            let o = i * 4
            let r = Double(ptr[o]) / 255.0
            let g = Double(ptr[o + 1]) / 255.0
            let b = Double(ptr[o + 2]) / 255.0
            sum += LineStyle.luminance(r: r, g: g, b: b)
        }
        return sum / Double(count)
    }
}
