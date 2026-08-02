import UIKit

enum CompanyLogoSupport {
    /// Stores logo as `data:image/jpeg;base64,...` for JSON export and PDF loading (matches `InvoicePDFGenerator.loadLogoImage`).
    static func dataURI(from image: UIImage, maxDimension: CGFloat = 800, compression: CGFloat = 0.75) -> String? {
        let resized = resize(image, maxDimension: maxDimension)
        guard let data = resized.jpegData(compressionQuality: compression) else { return nil }
        return "data:image/jpeg;base64,\(data.base64EncodedString())"
    }

    private static func resize(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension else { return image }
        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
