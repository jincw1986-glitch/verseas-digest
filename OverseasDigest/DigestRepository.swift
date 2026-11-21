import Foundation
import ImageIO
import UIKit
import Vision

enum DigestError: Error, LocalizedError {
    case badStatus(Int)
    case undecodable

    var errorDescription: String? {
        switch self {
        case .badStatus:
            return "网络没有返回有效内容。"
        case .undecodable:
            return "这份数据无法读取。"
        }
    }
}

struct LoadedPicture: @unchecked Sendable {
    let image: UIImage
    /// 归一化矩形，原点在左上角，y 向下。
    let faces: [CGRect]
}

struct ImageLoadFailure: Error {}

final class DigestRepository: @unchecked Sendable {
    static let shared = DigestRepository()

    private let session: URLSession
    private let fileManager = FileManager.default
    private let cacheRoot: URL
    private let imageMemory = ImageMemory()
    private let library: ImageLibrary

    private init() {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        cacheRoot = support.appendingPathComponent("DigestCache", isDirectory: true)
        let libraryRoot = support.appendingPathComponent("DigestLibrary", isDirectory: true)
        try? fileManager.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        library = ImageLibrary(root: libraryRoot)
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 25
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    func loadIndex() -> IssueIndex? {
        if let cached = read(IssueIndex.self, from: cacheRoot.appendingPathComponent("index.json")) {
            return cached
        }
        guard let bundled = bundledFileURL(relativePath: "index.json") else { return nil }
        return read(IssueIndex.self, from: bundled)
    }

    func loadIssue(_ entry: IndexEntry) -> DigestIssue? {
        if let cached = read(DigestIssue.self, from: issueCacheURL(date: entry.date)), cached.date == entry.date {
            return cached
        }
        guard let bundled = bundledFileURL(relativePath: entry.path),
              let issue = read(DigestIssue.self, from: bundled),
              issue.date == entry.date else {
            return nil
        }
        return issue
    }

    func fetchIndex() async throws -> IssueIndex {
        let data = try await fetchData(from: DigestConfig.remoteURL(relativePath: "index.json"))
        let index = try decode(IssueIndex.self, from: data)
        try store(data, to: cacheRoot.appendingPathComponent("index.json"))
        return index
    }

    func fetchIssue(_ entry: IndexEntry) async throws -> DigestIssue {
        let data = try await fetchData(from: DigestConfig.remoteURL(relativePath: entry.path))
        let issue = try decode(DigestIssue.self, from: data)
        guard issue.date == entry.date else { throw DigestError.undecodable }
        try store(data, to: issueCacheURL(date: entry.date))
        return issue
    }

    /// 安装包里的副本优先，其次是已经下载过的磁盘缓存，最后才请求网络。
    /// 下载放在不会被界面取消的任务里：分页容器会取消视图上的 `.task`，不能因此把图丢掉。
    func loadPicture(_ picture: DigestPicture) async throws -> LoadedPicture {
        let key = picture.cacheKey
        guard !key.isEmpty else { throw ImageLoadFailure() }
        if let cached = imageMemory.cached(key) { return cached }
        let task = imageMemory.task(for: key) {
            Task.detached(priority: .userInitiated) { () async throws -> LoadedPicture in
                do {
                    let loaded = try await self.fetchAndDecode(picture)
                    self.imageMemory.finish(key, loaded)
                    return loaded
                } catch {
                    self.imageMemory.fail(key)
                    throw error
                }
            }
        }
        return try await task.value
    }

    private func fetchAndDecode(_ picture: DigestPicture) async throws -> LoadedPicture {
        guard let data = await acquireImageData(for: picture), let image = decodeImage(data) else {
            throw ImageLoadFailure()
        }
        return makePicture(image)
    }

    /// 先读本机永久图库，再读缓存和安装包，最后才下载。成功的图会写入图库。
    func acquireImageData(for picture: DigestPicture) async -> Data? {
        let keys = sourceKeys(for: picture)
        if let stored = library.data(matching: keys), decodeImage(stored) != nil {
            return stored
        }
        if let path = picture.path, !path.isEmpty {
            if let bundled = readBundleData(relativePath: path), decodeImage(bundled) != nil {
                library.store(bundled, keys: keys, ext: fileExtension(of: path))
                return bundled
            }
            let cachedURL = imageCacheURL(relativePath: path)
            if let cached = readValidImage(at: cachedURL) {
                library.store(cached, keys: keys, ext: fileExtension(of: path))
                return cached
            }
            let remote = DigestConfig.remoteURL(relativePath: path)
            if let downloaded = await downloadWithRetry(remote) {
                try? store(downloaded, to: cachedURL)
                var savedKeys = keys
                savedKeys.append(remote.absoluteString)
                library.store(downloaded, keys: savedKeys, ext: fileExtension(of: path))
                return downloaded
            }
        }
        if let urlString = picture.url, let remote = URL(string: urlString), remote.scheme == "https" {
            let disk = remoteImageCacheURL(for: urlString)
            if let cached = readValidImage(at: disk) {
                library.store(cached, keys: keys + [urlString], ext: fileExtension(of: urlString))
                return cached
            }
            if let downloaded = await downloadWithRetry(remote) {
                try? store(downloaded, to: disk)
                library.store(downloaded, keys: keys + [urlString], ext: fileExtension(of: urlString))
                return downloaded
            }
        }
        return nil
    }

    func sourceKeys(for picture: DigestPicture) -> [String] {
        var keys: [String] = []
        if let path = picture.path, !path.isEmpty {
            keys.append(path)
            keys.append(DigestConfig.remoteURL(relativePath: path).absoluteString)
        }
        if let url = picture.url, !url.isEmpty {
            keys.append(url)
        }
        return keys
    }

    func fileExtension(of name: String) -> String {
        let ext = URL(string: name)?.pathExtension.lowercased() ?? ""
        if ["jpg", "jpeg", "png", "webp"].contains(ext) { return ext }
        let fallback = (name as NSString).pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "webp"].contains(fallback) { return fallback }
        return "jpg"
    }

    func clearPictureMemory() {
        imageMemory.removeAll()
    }

    func cachedIndexData() -> Data? {
        let url = cacheRoot.appendingPathComponent("index.json")
        if let data = try? Data(contentsOf: url) { return data }
        guard let bundled = bundledFileURL(relativePath: "index.json") else { return nil }
        return try? Data(contentsOf: bundled)
    }

    func cachedIssueData(for entry: IndexEntry) -> Data? {
        let cached = issueCacheURL(date: entry.date)
        if let data = try? Data(contentsOf: cached) { return data }
        guard let bundled = bundledFileURL(relativePath: entry.path) else { return nil }
        return try? Data(contentsOf: bundled)
    }

    func mergeImportedIssues(_ imported: IssueIndex, payloads: [String: Data]) throws -> Int {
        var byDate: [String: IndexEntry] = [:]
        if let current = loadIndex() {
            for entry in current.issues {
                byDate[entry.date] = entry
            }
        }
        var added = 0
        for entry in imported.issues {
            if byDate[entry.date] != nil { continue }
            let key = entry.path
            let payload = payloads[key] ?? payloads["issues/\(entry.date).json"]
            guard let payload else { continue }
            let issue = try decode(DigestIssue.self, from: payload)
            guard issue.date == entry.date else { continue }
            try store(payload, to: issueCacheURL(date: entry.date))
            byDate[entry.date] = entry
            added += 1
        }
        let merged = IssueIndex(issues: byDate.values.sorted { $0.date > $1.date })
        let encoded = try JSONEncoder().encode(merged)
        try store(encoded, to: cacheRoot.appendingPathComponent("index.json"))
        return added
    }

    func storeImportedImages(_ groups: [(keys: [String], data: Data)]) -> Int {
        var stored = 0
        for group in groups {
            let keys = group.keys.filter { !$0.isEmpty }
            guard !keys.isEmpty, decodeImage(group.data) != nil else { continue }
            let already = library.data(matching: keys) != nil && keys.allSatisfy { library.contains($0) }
            if already { continue }
            library.store(group.data, keys: keys, ext: fileExtension(of: keys[0]))
            stored += 1
        }
        return stored
    }

    private func downloadWithRetry(_ url: URL) async -> Data? {
        do {
            return try await fetchImageData(from: url)
        } catch {
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
            } catch {
                return nil
            }
            do {
                return try await fetchImageData(from: url)
            } catch {
                return nil
            }
        }
    }

    private func readBundleData(relativePath: String) -> Data? {
        guard let url = bundledFileURL(relativePath: relativePath) else { return nil }
        return try? Data(contentsOf: url)
    }

    private func readValidImage(at url: URL) -> Data? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if decodeImage(data) != nil { return data }
        try? fileManager.removeItem(at: url)
        return nil
    }

    private func fetchImageData(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .useProtocolCachePolicy
        request.timeoutInterval = 30
        request.setValue("verseas-digest/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("image/jpeg,image/png,image/*;q=0.8,*/*;q=0.5", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ImageLoadFailure()
        }
        if let type = http.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
           type.contains("text/html") || type.contains("application/json") {
            throw ImageLoadFailure()
        }
        guard data.count > 32, decodeImage(data) != nil else { throw ImageLoadFailure() }
        return data
    }

    private func makePicture(_ image: UIImage) -> LoadedPicture {
        LoadedPicture(image: image, faces: detectFaces(in: image))
    }

    private func decodeImage(_ data: Data) -> UIImage? {
        if let image = UIImage(data: data), image.size.width > 1, image.size.height > 1 {
            return image
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return UIImage(cgImage: cgImage, scale: 1, orientation: imageOrientation(from: source))
    }

    private func imageOrientation(from source: CGImageSource) -> UIImage.Orientation {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let raw = properties[kCGImagePropertyOrientation] as? UInt32,
              let cgOrientation = CGImagePropertyOrientation(rawValue: raw) else { return .up }
        switch cgOrientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }

    private func detectFaces(in image: UIImage) -> [CGRect] {
        guard let cgImage = image.cgImage else { return [] }
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: CGImagePropertyOrientation(image.imageOrientation),
            options: [:]
        )
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        let observations = (request.results ?? []).compactMap { $0 as VNFaceObservation? }
        return observations.map { observation in
            let box = observation.boundingBox
            return CGRect(
                x: box.origin.x,
                y: 1 - box.origin.y - box.height,
                width: box.size.width,
                height: box.size.height
            )
        }
    }

    private func fetchData(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 25
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DigestError.badStatus(-1) }
        guard (200..<300).contains(http.statusCode) else { throw DigestError.badStatus(http.statusCode) }
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw DigestError.undecodable
        }
    }

    private func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func store(_ data: Data, to url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private func issueCacheURL(date: String) -> URL {
        cacheRoot.appendingPathComponent("issues", isDirectory: true).appendingPathComponent("\(date).json")
    }

    private func imageCacheURL(relativePath: String) -> URL {
        relativePath.split(separator: "/").map(String.init).reduce(cacheRoot) { url, part in
            url.appendingPathComponent(part)
        }
    }

    private func remoteImageCacheURL(for urlString: String) -> URL {
        cacheRoot
            .appendingPathComponent("remote-images", isDirectory: true)
            .appendingPathComponent(stableFilename(for: urlString))
    }

    private func bundledFileURL(relativePath: String) -> URL? {
        let parts = relativePath.split(separator: "/").map(String.init).filter { !$0.isEmpty && $0 != "." && $0 != ".." }
        guard let file = parts.last else { return nil }
        let name = (file as NSString).deletingPathExtension
        let ext = (file as NSString).pathExtension
        let directories = [
            (["data"] + parts.dropLast()).joined(separator: "/"),
            parts.dropLast().joined(separator: "/")
        ]
        for directory in directories where !directory.isEmpty {
            if let url = Bundle.main.url(forResource: name, withExtension: ext.isEmpty ? nil : ext, subdirectory: directory) {
                return url
            }
        }
        let roots = [Bundle.main.bundleURL, Bundle.main.resourceURL].compactMap { $0 }
        for root in roots {
            let withData = parts.reduce(root.appendingPathComponent("data", isDirectory: true)) { url, part in
                url.appendingPathComponent(part)
            }
            let direct = parts.reduce(root) { url, part in
                url.appendingPathComponent(part)
            }
            for candidate in [withData, direct] where fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    private func stableFilename(for string: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        let ext = URL(string: string)?.pathExtension.lowercased() ?? ""
        let safe = ["jpg", "jpeg", "png", "webp"].contains(ext) ? ext : "img"
        return "\(hash).\(safe)"
    }
}

private final class ImageMemory: @unchecked Sendable {
    private let lock = NSLock()
    private var images: [String: LoadedPicture] = [:]
    private var inflight: [String: Task<LoadedPicture, Error>] = [:]

    func cached(_ key: String) -> LoadedPicture? {
        lock.lock()
        defer { lock.unlock() }
        return images[key]
    }

    func task(for key: String, create: () -> Task<LoadedPicture, Error>) -> Task<LoadedPicture, Error> {
        lock.lock()
        defer { lock.unlock() }
        if let existing = inflight[key] { return existing }
        let created = create()
        inflight[key] = created
        return created
    }

    func finish(_ key: String, _ picture: LoadedPicture) {
        lock.lock()
        defer { lock.unlock() }
        images[key] = picture
        inflight[key] = nil
    }

    func fail(_ key: String) {
        lock.lock()
        defer { lock.unlock() }
        inflight[key] = nil
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        images.removeAll()
    }
}

private final class ImageLibrary: @unchecked Sendable {
    private struct IndexFile: Codable {
        var files: [String: String] = [:]
    }

    private let root: URL
    private let indexURL: URL
    private let lock = NSLock()
    private var files: [String: String] = [:]
    private var loaded = false

    init(root: URL) {
        self.root = root
        indexURL = root.appendingPathComponent("files.json")
    }

    func contains(_ key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeeded()
        return files[key] != nil
    }

    func data(matching keys: [String]) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeeded()
        for key in keys {
            guard let name = files[key] else { continue }
            let url = root.appendingPathComponent(name)
            if let data = try? Data(contentsOf: url), !data.isEmpty {
                return data
            }
        }
        return nil
    }

    func store(_ data: Data, keys: [String], ext: String) {
        let usable = keys.filter { !$0.isEmpty }
        guard !usable.isEmpty, !data.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        loadIfNeeded()
        var filename: String?
        for key in usable {
            if let existing = files[key] {
                filename = existing
                break
            }
        }
        if filename == nil {
            let safeExt = ["jpg", "jpeg", "png", "webp"].contains(ext) ? ext : "jpg"
            filename = "images/\(Self.stableName(usable[0])).\(safeExt)"
            let url = root.appendingPathComponent(filename!)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
        guard let filename else { return }
        var changed = false
        for key in usable where files[key] != filename {
            files[key] = filename
            changed = true
        }
        if changed {
            let encoded = (try? JSONEncoder().encode(IndexFile(files: files))) ?? Data()
            try? encoded.write(to: indexURL, options: .atomic)
        }
    }

    private func loadIfNeeded() {
        if loaded { return }
        loaded = true
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode(IndexFile.self, from: data) else { return }
        files = decoded.files
    }

    private static func stableName(_ string: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash)
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
