import SwiftUI
import UIKit

/// Profile picture (data URL or http URL as stored by the web app) or initials.
struct AvatarView: View {
    let url: String?
    let name: String
    var size: CGFloat = 72

    var body: some View {
        Group {
            if let image = Self.decodeDataURL(url) {
                Image(uiImage: image).resizable().scaledToFill()
            } else if let raw = url, raw.hasPrefix("http"), let remote = URL(string: raw) {
                AsyncImage(url: remote) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        initials
                    }
                }
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }

    private var initials: some View {
        ZStack {
            LinearGradient(colors: [.accentColor.opacity(0.85), .accentColor.opacity(0.55)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(verbatim: Self.initials(name))
                .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    /// First letters of up to two words, like the web app.
    static func initials(_ name: String) -> String {
        let letters = name.split(separator: " ").compactMap(\.first).map(String.init).joined()
        return String(letters.uppercased().prefix(2))
    }

    static func decodeDataURL(_ raw: String?) -> UIImage? {
        guard let raw, raw.hasPrefix("data:"), let comma = raw.firstIndex(of: ",") else { return nil }
        guard let data = Data(base64Encoded: String(raw[raw.index(after: comma)...]),
                              options: .ignoreUnknownCharacters) else { return nil }
        return UIImage(data: data)
    }

    /// Center square crop, 256 px, JPEG data URL (stored in the profile).
    static func dataURL(from data: Data, side: CGFloat = 256) -> String? {
        guard let image = UIImage(data: data) else { return nil }
        let size = image.size
        let crop = min(size.width, size.height)
        guard crop > 0 else { return nil }
        let scale = side / crop
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        let square = renderer.image { _ in
            image.draw(in: CGRect(x: -(size.width - crop) / 2 * scale,
                                  y: -(size.height - crop) / 2 * scale,
                                  width: size.width * scale,
                                  height: size.height * scale))
        }
        guard let jpeg = square.jpegData(compressionQuality: 0.85) else { return nil }
        return "data:image/jpeg;base64," + jpeg.base64EncodedString()
    }
}
