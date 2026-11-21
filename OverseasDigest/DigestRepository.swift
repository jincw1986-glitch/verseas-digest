import Foundation

enum DigestError: Error {
    case badStatus(Int)
    case undecodable
}

final class DigestRepository {
    static let shared = DigestRepository()

    private let session: URLSession
    private let fileManager = FileManager.default
    private let cacheRoot: URL

    private init() {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        cacheRoot = support.appendingPathComponent("DigestCache", isDirectory: true)
        try? fileManager.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
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

    func imageData(for picture: DigestPicture) async -> Data? {
        if let path = picture.path, !path.isEmpty {
            let cached = imageCacheURL(relativePath: path)
            if let data = try? Data(contentsOf: cached), !data.isEmpty {
                return data
            }
            if let bundled = bundledFileURL(relativePath: path),
               let data = try? Data(contentsOf: bundled), !data.isEmpty {
                return data
            }
            if let data = try? await fetchData(from: DigestConfig.remoteURL(relativePath: path)), !data.isEmpty {
                try? store(data, to: cached)
                return data
            }
        }
        if let urlString = picture.url, let remote = URL(string: urlString), remote.scheme == "https" {
            let cached = remoteImageCacheURL(for: urlString)
            if let data = try? Data(contentsOf: cached), !data.isEmpty {
                return data
            }
            if let data = try? await fetchData(from: remote), !data.isEmpty {
                try? store(data, to: cached)
                return data
            }
        }
        return nil
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
        let root = Bundle.main.bundleURL.appendingPathComponent("data", isDirectory: true)
        let full = relativePath.split(separator: "/").map(String.init).reduce(root) { url, part in
            url.appendingPathComponent(part)
        }
        return fileManager.fileExists(atPath: full.path) ? full : nil
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
