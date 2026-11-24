import SafariServices
import SwiftUI
import UIKit

extension Color {
    static let jokePaper = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.28, green: 0.22, blue: 0.12, alpha: 1)
        }
        return UIColor(red: 1.0, green: 0.97, blue: 0.90, alpha: 1)
    })

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

extension NewsImportance {
    var color: Color {
        switch self {
        case .major: Color(red: 0.55, green: 0.32, blue: 0.43)
        case .notable: Color(red: 0.67, green: 0.40, blue: 0.17)
        case .routine: Color(red: 0.40, green: 0.51, blue: 0.61)
        }
    }
}

struct NewsImportanceBadge: View {
    let importance: NewsImportance?

    var body: some View {
        let color = importance?.color ?? .secondary
        let label = importance?.label ?? "未评级"

        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 9, height: 9)
                .accessibilityHidden(true)
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.16), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("重要程度，\(label)")
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

enum PhotoFraming {
    /// 通栏大图：尽量铺满，并用脸的位置决定裁切，保证每张脸都完整。
    case hero
    /// 整张图放在模糊放大的背景上，不裁切。
    case full
}

struct DigestPhoto: View {
    let picture: DigestPicture?
    var accent: Color = Color(red: 0.22, green: 0.30, blue: 0.42)
    var symbol: String = "photo"
    var fillsFrame: Bool = false
    var framing: PhotoFraming = .hero
    var isInteractive = true
    @State private var phase: Phase = .idle
    @State private var showViewer = false
    @State private var loadToken = LoadToken()

    private enum Phase {
        case idle
        case loading
        case loaded(UIImage, [CGRect])
        case failed
    }

    private var hasPicture: Bool {
        guard let picture else { return false }
        return !(picture.path ?? "").isEmpty || !(picture.url ?? "").isEmpty
    }

    var body: some View {
        Group {
            if fillsFrame {
                photoStack
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Color.clear
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .overlay { photoStack }
            }
        }
        .clipped()
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { if isInteractive { handleTap() } })
        .onAppear { beginLoad(force: false) }
        .onChange(of: picture?.cacheKey) { _, _ in
            phase = .idle
            beginLoad(force: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(hasPicture && isInteractive ? .isButton : AccessibilityTraits())
        .fullScreenCover(isPresented: $showViewer) {
            if case .loaded(let image, _) = phase {
                ImageViewer(image: image, credit: picture?.credit ?? "")
            }
        }
    }

    private var accessibilityText: String {
        switch phase {
        case .failed:
            return isInteractive ? "图片没有载入，轻点重试" : "图片没有载入"
        case .loaded:
            return isInteractive ? "查看大图。\(picture?.credit ?? "")" : picture?.credit ?? "图片"
        case .loading:
            return "正在载入图片"
        case .idle:
            return picture?.credit ?? "图片"
        }
    }

    @ViewBuilder
    private var photoStack: some View {
        switch phase {
        case .loaded(let image, let faces):
            FittedPhoto(image: image, faces: faces, framing: framing)
        case .failed:
            statusFill(title: "图片没有载入", detail: isInteractive ? "轻点重试" : nil, spinning: false)
        case .loading where hasPicture:
            statusFill(title: "正在载入图片", detail: nil, spinning: true)
        default:
            accentFill
        }
    }

    private var accentFill: some View {
        ZStack {
            LinearGradient(
                colors: [accent.opacity(0.95), accent.opacity(0.55)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    private func statusFill(title: String, detail: String?, spinning: Bool) -> some View {
        ZStack {
            accentFill
            VStack(spacing: 8) {
                if spinning {
                    ProgressView()
                        .tint(.white)
                }
                Text(title)
                    .font(.footnote.weight(.semibold))
                if let detail {
                    Text(detail)
                        .font(.caption.weight(.medium))
                }
            }
            .foregroundStyle(.white)
            .padding(12)
            .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func beginLoad(force: Bool) {
        guard hasPicture, let picture else { return }
        if !force {
            if case .loading = phase { return }
            if case .loaded = phase { return }
        }
        phase = .loading
        loadToken.value += 1
        let token = loadToken.value
        let gate = loadToken
        let requested = picture
        Task {
            do {
                let loaded = try await DigestRepository.shared.loadPicture(requested)
                guard token == gate.value else { return }
                phase = .loaded(loaded.image, loaded.faces)
            } catch {
                guard token == gate.value else { return }
                phase = .failed
            }
        }
    }

    private func handleTap() {
        switch phase {
        case .failed:
            beginLoad(force: true)
        case .loaded:
            showViewer = true
        default:
            break
        }
    }
}

private final class LoadToken {
    var value = 0
}

private struct FittedPhoto: View {
    let image: UIImage
    let faces: [CGRect]
    let framing: PhotoFraming

    var body: some View {
        GeometryReader { geo in
            let layout = PhotoLayout.resolve(
                imageSize: image.size,
                faces: faces,
                framing: framing,
                container: geo.size
            )
            if layout.letterbox {
                ZStack {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .blur(radius: 18)
                        .overlay(Color.black.opacity(0.25))
                        .clipped()
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            } else {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: layout.drawSize.width, height: layout.drawSize.height)
                    .offset(layout.offset)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                    .clipped()
            }
        }
    }
}

private struct PhotoLayout {
    var letterbox: Bool
    var drawSize: CGSize
    var offset: CGSize

    static func resolve(imageSize: CGSize, faces: [CGRect], framing: PhotoFraming, container: CGSize) -> PhotoLayout {
        let imgW = imageSize.width
        let imgH = imageSize.height
        guard imgW > 1, imgH > 1, container.width > 1, container.height > 1 else {
            return PhotoLayout(letterbox: true, drawSize: container, offset: .zero)
        }
        if framing == .full {
            return PhotoLayout(letterbox: true, drawSize: container, offset: .zero)
        }
        let portrait = imgH >= imgW
        if portrait && !faces.isEmpty {
            return PhotoLayout(letterbox: true, drawSize: container, offset: .zero)
        }
        let scale = max(container.width / imgW, container.height / imgH)
        let visW = container.width / scale
        let visH = container.height / scale
        let drawSize = CGSize(width: imgW * scale, height: imgH * scale)
        let origin: CGPoint
        if faces.isEmpty {
            origin = CGPoint(x: max((imgW - visW) / 2, 0), y: portrait ? 0 : max((imgH - visH) / 2, 0))
        } else if let fitted = originContainingFaces(
            faces,
            imageWidth: imgW,
            imageHeight: imgH,
            visibleWidth: visW,
            visibleHeight: visH
        ) {
            origin = fitted
        } else {
            return PhotoLayout(letterbox: true, drawSize: container, offset: .zero)
        }
        return PhotoLayout(
            letterbox: false,
            drawSize: drawSize,
            offset: CGSize(width: -origin.x * scale, height: -origin.y * scale)
        )
    }

    /// 返回能装下所有脸的可见窗口左上角。装不下时返回 nil，调用方改为完整显示。
    private static func originContainingFaces(
        _ faces: [CGRect],
        imageWidth: CGFloat,
        imageHeight: CGFloat,
        visibleWidth: CGFloat,
        visibleHeight: CGFloat
    ) -> CGPoint? {
        let raw = union(faces, imageWidth: imageWidth, imageHeight: imageHeight, pad: 0)
        let padded = union(faces, imageWidth: imageWidth, imageHeight: imageHeight, pad: 0.28)
        let target = padded.width <= visibleWidth && padded.height <= visibleHeight ? padded : raw
        guard target.width <= visibleWidth + 0.5, target.height <= visibleHeight + 0.5 else { return nil }
        let maxX = max(imageWidth - visibleWidth, 0)
        let maxY = max(imageHeight - visibleHeight, 0)
        var x = min(max(target.midX - visibleWidth / 2, 0), maxX)
        var y = min(max(target.midY - visibleHeight / 2, 0), maxY)
        if x > target.minX { x = min(max(target.minX, 0), maxX) }
        if x + visibleWidth < target.maxX { x = min(max(target.maxX - visibleWidth, 0), maxX) }
        if y > target.minY { y = min(max(target.minY, 0), maxY) }
        if y + visibleHeight < target.maxY { y = min(max(target.maxY - visibleHeight, 0), maxY) }
        guard x <= target.minX + 0.5, x + visibleWidth + 0.5 >= target.maxX else { return nil }
        guard y <= target.minY + 0.5, y + visibleHeight + 0.5 >= target.maxY else { return nil }
        return CGPoint(x: x, y: y)
    }

    private static func union(_ faces: [CGRect], imageWidth: CGFloat, imageHeight: CGFloat, pad: CGFloat) -> CGRect {
        var rect = CGRect.null
        guard !faces.isEmpty else { return .zero }
        for face in faces {
            var box = CGRect(
                x: face.minX * imageWidth,
                y: face.minY * imageHeight,
                width: face.width * imageWidth,
                height: face.height * imageHeight
            )
            box = box.insetBy(dx: -box.width * pad, dy: -box.height * pad)
            box.origin.y -= box.height * 0.12
            box.size.height += box.height * 0.12
            rect = rect.union(box)
        }
        let clipped = rect.intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
        return clipped.isNull ? .zero : clipped
    }
}

private struct ImageViewer: View {
    let image: UIImage
    let credit: String
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .gesture(zoomGesture)
                .simultaneousGesture(panGesture)
                .onTapGesture(count: 2) {
                    if scale > 1.05 {
                        scale = 1
                        baseScale = 1
                        offset = .zero
                        baseOffset = .zero
                    } else {
                        scale = 2
                        baseScale = 2
                    }
                }
        }
        .overlay(alignment: .topTrailing) {
            Button("关闭") { dismiss() }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .padding()
        }
        .overlay(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(credit)
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text("双指缩放，下拉关闭")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.75))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.black.opacity(0.55))
        }
        .statusBarHidden(true)
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(max(baseScale * value.magnification, 0.85), 4)
            }
            .onEnded { _ in
                if scale < 1 {
                    scale = 1
                    baseScale = 1
                    offset = .zero
                    baseOffset = .zero
                } else {
                    baseScale = scale
                }
            }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if scale <= 1.02 {
                    offset = CGSize(width: 0, height: max(value.translation.height, -12))
                } else {
                    offset = CGSize(
                        width: baseOffset.width + value.translation.width,
                        height: baseOffset.height + value.translation.height
                    )
                }
            }
            .onEnded { value in
                if scale <= 1.02 {
                    if value.translation.height > 90 {
                        dismiss()
                    } else {
                        offset = .zero
                        baseOffset = .zero
                    }
                } else {
                    baseOffset = offset
                }
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

struct JokeCard: View {
    let joke: JokeItem
    let onOpen: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("“")
                .font(.system(size: 42, weight: .bold, design: .serif))
                .foregroundStyle(Color.orange)
                .frame(height: 28, alignment: .top)
                .accessibilityHidden(true)
            Text(joke.text)
                .font(.system(.title3, design: .serif))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if let translation = joke.translation, !translation.isEmpty {
                Text(translation)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            if let note = joke.note, !note.isEmpty {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let url = joke.postURL {
                Button {
                    onOpen(url)
                } label: {
                    Text("\(joke.authorName)  \(joke.handle)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("打开 \(joke.authorName) 的帖子")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.jokePaper, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
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
