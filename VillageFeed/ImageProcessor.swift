import UIKit

enum ImageProcessor {
    /// Downscales to `maxDimension` on the long edge and re-encodes as JPEG.
    /// Library picks are often 10MB+ HEIC; cards need ~1200px at most.
    static func jpegData(from data: Data, maxDimension: CGFloat = 1200, quality: CGFloat = 0.8) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longEdge = max(image.size.width, image.size.height)
        guard longEdge > 0 else { return nil }
        let scale = min(1, maxDimension / longEdge)
        if scale >= 1 {
            return image.jpegData(compressionQuality: quality)
        }
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}
