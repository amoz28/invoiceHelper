import PhotosUI
import SwiftUI
import UIKit

/// Renders company `logo` from data URI, `file://`, `http(s)`, or local path (same rules as PDF).
struct CompanyLogoImageView: View {
    let logo: String?
    var size: CGFloat = 44
    var clipCircle: Bool = true
    /// When true, letterbox inside the frame (good for profile tiles); when false, fills and clips (avatars).
    var scaleToFit: Bool = false
    /// Subtle border (disable in tight toolbar slots to avoid “padding” look).
    var showsStroke: Bool = true

    var body: some View {
        Group {
            if let uri = logo?.trimmingCharacters(in: .whitespacesAndNewlines), !uri.isEmpty {
                if uri.hasPrefix("data:image"), let comma = uri.firstIndex(of: ",") {
                    let b64 = String(uri[uri.index(after: comma)...])
                    if let data = Data(base64Encoded: b64), let ui = UIImage(data: data) {
                        Image(uiImage: ui)
                            .resizable()
                            .aspectRatio(contentMode: scaleToFit ? .fit : .fill)
                    } else {
                        placeholder
                    }
                } else if uri.hasPrefix("file://"), let url = URL(string: uri),
                          let data = try? Data(contentsOf: url), let ui = UIImage(data: data) {
                    Image(uiImage: ui)
                        .resizable()
                        .aspectRatio(contentMode: scaleToFit ? .fit : .fill)
                } else if uri.hasPrefix("/"), let data = try? Data(contentsOf: URL(fileURLWithPath: uri)),
                          let ui = UIImage(data: data) {
                    Image(uiImage: ui)
                        .resizable()
                        .aspectRatio(contentMode: scaleToFit ? .fit : .fill)
                } else if let url = URL(string: uri), url.scheme == "http" || url.scheme == "https" {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().aspectRatio(contentMode: scaleToFit ? .fit : .fill)
                        default:
                            placeholder
                        }
                    }
                } else {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: clipCircle ? size / 2 : 12, style: .continuous))
        .overlay {
            if showsStroke {
                RoundedRectangle(cornerRadius: clipCircle ? size / 2 : 12, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
            }
        }
    }

    private var placeholder: some View {
        Image(systemName: "building.2.fill")
            .font(.system(size: size * 0.45))
            .foregroundStyle(AppTheme.infoBlue)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.secondarySystemFill))
    }
}

/// Logo picker + preview for company profile (registration, edit, settings).
struct CompanyLogoSection: View {
    @Binding var logoDataURI: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var loadError: String?

    var body: some View {
        Section {
            HStack(alignment: .center, spacing: 16) {
                CompanyLogoImageView(logo: logoDataURI, size: 88, clipCircle: false, scaleToFit: true)
                    .background(Color(.secondarySystemFill))

                VStack(alignment: .leading, spacing: 8) {
                    PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                        Label("Choose logo", systemImage: "photo.on.rectangle.angled")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)

                    if logoDataURI != nil {
                        Button("Remove logo", role: .destructive) {
                            logoDataURI = nil
                            photoItem = nil
                        }
                        .font(.subheadline)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)

            Text("Shown on invoices, estimates, and your company profile. Square images work best.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Company logo")
        }
        .onChange(of: photoItem) { _, new in
            guard let new else { return }
            Task { await loadPhoto(new) }
        }
        if let loadError {
            Section {
                Text(loadError).foregroundStyle(.red).font(.caption)
            }
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        loadError = nil
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let ui = UIImage(data: data),
                  let uri = CompanyLogoSupport.dataURI(from: ui)
            else {
                await MainActor.run { loadError = "Could not read image." }
                return
            }
            await MainActor.run { logoDataURI = uri }
        } catch {
            await MainActor.run { loadError = error.localizedDescription }
        }
    }
}
