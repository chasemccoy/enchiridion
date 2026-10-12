import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import EnchiridionCore

struct WidgetContentTests {
    @Test func markdownBecomesPlainLines() {
        let markdown = """
        # A heading

        Some *emphasis*, `code` and a [link](https://example.com).

        > A quote
        - one
        2. two
        ---
        """
        #expect(WidgetContent.excerpt(markdown) == "A heading\nSome emphasis, code and a link.\nA quote\none\ntwo")
    }

    @Test func longTextIsCutAtAWord() {
        let excerpt = WidgetContent.excerpt("alpha beta gamma delta", limit: 13)
        #expect(excerpt == "alpha beta…")
        #expect(WidgetContent.excerpt("  \n\n ") == nil)
        #expect(WidgetContent.excerpt(nil) == nil)
    }

    @Test func thumbnailsAreSmallJPEGs() throws {
        let png = try #require(Self.png(width: 2000, height: 1000))
        let thumbnail = try #require(WidgetContent.thumbnail(png, maxPixelSize: 400))
        let source = try #require(CGImageSourceCreateWithData(thumbnail as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier)
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 400)
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == 200)
        #expect(WidgetContent.thumbnail(Data("<svg/>".utf8), maxPixelSize: 400) == nil)
    }

    private static func png(width: Int, height: Int) -> Data? {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
