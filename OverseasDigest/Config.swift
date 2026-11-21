import Foundation

/// 网络地址只放在这里。每日数据更新后，App 会从该目录读取 index.json 和各期 JSON。
enum DigestConfig {
    static let baseURL = URL(string: "https://raw.githubusercontent.com/jincw1986-glitch/verseas-digest/main/data")!

    /// 按路径段拼到 baseURL 后面。不用 `appendingPathComponent`：在部分系统上，
    /// 它会把没有以斜线结尾的 https 地址的最后一段替换掉，图片就会请求到错误地址。
    static func remoteURL(relativePath: String) -> URL {
        let root = baseURL.absoluteString.hasSuffix("/")
            ? String(baseURL.absoluteString.dropLast())
            : baseURL.absoluteString
        let encoded = relativePath.split(separator: "/").map { segment -> String in
            let piece = String(segment)
            return piece.addingPercentEncoding(withAllowedCharacters: pathSegmentAllowed) ?? piece
        }.joined(separator: "/")
        guard !encoded.isEmpty, let url = URL(string: root + "/" + encoded) else { return baseURL }
        return url
    }

    private static let pathSegmentAllowed: CharacterSet = {
        var set = CharacterSet.urlPathAllowed
        set.remove(charactersIn: "/?#")
        return set
    }()
}
