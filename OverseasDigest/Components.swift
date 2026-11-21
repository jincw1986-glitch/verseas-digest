import SafariServices
import SwiftUI
import UIKit

extension Color {
    static let glossaryBlue = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.18, green: 0.42, blue: 0.86, alpha: 1)
        }
        return UIColor(red: 0.11, green: 0.35, blue: 0.78, alpha: 1)
    })
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
    }
}

struct GlossaryPill: View {
    let title: String
    let action: () -> Void
    @ScaledMetric(relativeTo: .subheadline) private var horizontal: CGFloat = 12
    @ScaledMetric(relativeTo: .subheadline) private var vertical: CGFloat = 10

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, horizontal)
                .padding(.vertical, vertical)
                .background(Color.glossaryBlue, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("名词解释：\(title)")
        .accessibilityHint("打开说明")
    }
}

struct GlossaryBlock: View {
    let entries: [GlossaryEntry]
    let onSelect: (GlossaryEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("名词解释")
                .font(.headline)
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 8) {
                    GlossaryPill(title: entry.term) {
                        onSelect(entry)
                    }
                    Text(entry.explanation)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct GlossarySheet: View {
    let entry: GlossaryEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(entry.type.label)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                    Text(entry.term)
                        .font(.title.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(entry.explanation)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .navigationTitle("名词解释")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

struct SourceButtons: View {
    let sources: [SourceLink]
    let onOpen: (URL) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(Array(sources.enumerated()), id: \.offset) { _, source in
                if let url = source.webURL {
                    Button {
                        onOpen(url)
                    } label: {
                        Label(source.name, systemImage: "safari")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("打开来源 \(source.name)")
                }
            }
        }
    }
}

struct SafariSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.preferredControlTintColor = .systemBlue
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

struct DigestPhoto: View {
    let picture: DigestPicture
    @State private var uiImage: UIImage?

    var body: some View {
        Color.clear
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay {
                if let uiImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Color.secondary.opacity(0.12)
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .clipped()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(picture.credit)
            .task(id: picture.cacheKey) {
                guard let data = await DigestRepository.shared.imageData(for: picture) else { return }
                uiImage = UIImage(data: data)
            }
    }
}

struct WebLink: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

enum PresentedSheet: Identifiable {
    case web(WebLink)
    case glossary(GlossaryEntry)

    var id: String {
        switch self {
        case .web(let link):
            return "web-\(link.id)"
        case .glossary(let entry):
            return "glossary-\(entry.id)-\(entry.explanation.hashValue)"
        }
    }
}

struct SheetContent: View {
    let presented: PresentedSheet

    var body: some View {
        switch presented {
        case .web(let link):
            SafariSheet(url: link.url)
                .ignoresSafeArea()
        case .glossary(let entry):
            GlossarySheet(entry: entry)
        }
    }
}

struct RefreshButton: View {
    @EnvironmentObject private var model: DigestModel

    var body: some View {
        Button {
            Task { await model.refresh() }
        } label: {
            if model.isRefreshing {
                ProgressView()
            } else {
                Image(systemName: "arrow.clockwise")
            }
        }
        .disabled(model.isRefreshing)
        .accessibilityLabel("刷新")
    }
}
