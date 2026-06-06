import Foundation
import CoreGraphics
import ImageIO
import AVFoundation

/// 單一檔案的畫質評估結果。
struct QualityScore {
    var sharpness: Double   // 梯度能量，越大越銳利
    var brightness: Double  // 0–255 平均亮度
    var isBlurry: Bool
    var isBadExposure: Bool
    /// 是否該保留（畫質 OK）。
    var keep: Bool { !isBlurry && !isBadExposure }
}

/// 純本機畫質分析：用清晰度（梯度能量）與曝光（平均亮度）判斷一個照片/影片好不好。
/// 不連網、不花錢、不外傳。閾值是經驗值，可依你的素材微調。
enum QualityAnalyzer {

    // MARK: - 可調閾值

    /// 清晰度低於此值視為模糊。素材偏暗或低對比時可調低。
    static var sharpnessThreshold: Double = 60
    /// 平均亮度低於此值視為過暗。
    static var darkThreshold: Double = 22
    /// 平均亮度高於此值視為過曝。
    static var brightThreshold: Double = 238

    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "heic", "heif", "png", "tif", "tiff", "gif", "bmp", "webp",
        "dng", "raw", "cr2", "cr3", "nef", "nrw", "arw", "sr2", "srf",
        "raf", "orf", "rw2", "pef", "x3f", "3fr", "erf",
    ]
    private static let videoExtensions: Set<String> = [
        "mov", "mp4", "m4v", "avi", "mpg", "mpeg", "3gp", "3g2",
        "mts", "m2ts", "mxf", "wmv", "mkv", "webm",
    ]

    // MARK: - 對外入口

    static func analyze(_ url: URL) -> QualityScore? {
        let ext = url.pathExtension.lowercased()
        if imageExtensions.contains(ext) {
            guard let cg = loadImage(url) else { return nil }
            return score(frames: [cg])
        } else if videoExtensions.contains(ext) {
            let frames = videoFrames(url)
            guard !frames.isEmpty else { return nil }
            return score(frames: frames)
        }
        return nil
    }

    // MARK: - 評分

    /// 影片取多張取樣影格：清晰度取「最佳影格」（只要有一刻是清楚的就算數），
    /// 亮度取平均。照片就是單張。
    private static func score(frames: [CGImage]) -> QualityScore {
        var bestSharp = 0.0
        var brightnessSum = 0.0
        var n = 0
        for cg in frames {
            guard let (px, w, h) = grayPixels(from: cg) else { continue }
            bestSharp = max(bestSharp, sharpness(px, w, h))
            brightnessSum += brightness(px)
            n += 1
        }
        let avgBrightness = n > 0 ? brightnessSum / Double(n) : 0
        let blurry = bestSharp < sharpnessThreshold
        let badExposure = avgBrightness < darkThreshold || avgBrightness > brightThreshold
        return QualityScore(sharpness: bestSharp, brightness: avgBrightness,
                            isBlurry: blurry, isBadExposure: badExposure)
    }

    // MARK: - 影像處理

    /// 把影像縮小並轉成灰階像素陣列（最長邊 512，加速運算）。
    private static func grayPixels(from cg: CGImage, maxDim: Int = 512)
        -> (px: [UInt8], w: Int, h: Int)? {
        let longest = max(cg.width, cg.height)
        let scale = longest > maxDim ? Double(maxDim) / Double(longest) : 1.0
        let w = max(1, Int(Double(cg.width) * scale))
        let h = max(1, Int(Double(cg.height) * scale))
        var data = [UInt8](repeating: 0, count: w * h)
        let gray = CGColorSpaceCreateDeviceGray()
        // 在 withUnsafeMutableBytes 區塊內完成繪製，確保緩衝指標在 CGContext
        // 使用期間都有效（避免把 inout 指標的有效期延伸到呼叫之外）。
        let ok = data.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(
                data: raw.baseAddress, width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: w,
                space: gray, bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? (data, w, h) : nil
    }

    /// 清晰度 = 相鄰像素差的平方平均（梯度能量）。越清楚邊緣越強，值越大。
    private static func sharpness(_ px: [UInt8], _ w: Int, _ h: Int) -> Double {
        guard w > 1, h > 1 else { return 0 }
        var sum = 0.0
        var count = 0
        for y in 0..<h {
            let row = y * w
            for x in 1..<w {
                let dx = Double(px[row + x]) - Double(px[row + x - 1])
                sum += dx * dx
                count += 1
            }
        }
        return count > 0 ? sum / Double(count) : 0
    }

    private static func brightness(_ px: [UInt8]) -> Double {
        guard !px.isEmpty else { return 0 }
        var sum = 0.0
        for v in px { sum += Double(v) }
        return sum / Double(px.count)
    }

    // MARK: - 載入

    private static func loadImage(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    /// 從影片均勻取數張影格。
    private static func videoFrames(_ url: URL, count: Int = 5) -> [CGImage] {
        let asset = AVURLAsset(url: url)
        let duration = CMTimeGetSeconds(asset.duration)
        guard duration > 0 else { return [] }

        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 512, height: 512)
        gen.requestedTimeToleranceBefore = .positiveInfinity
        gen.requestedTimeToleranceAfter = .positiveInfinity

        var frames: [CGImage] = []
        for i in 1...count {
            let t = duration * Double(i) / Double(count + 1)
            let time = CMTime(seconds: t, preferredTimescale: 600)
            if let cg = try? gen.copyCGImage(at: time, actualTime: nil) {
                frames.append(cg)
            }
        }
        return frames
    }
}
