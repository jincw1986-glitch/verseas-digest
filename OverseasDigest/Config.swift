import Foundation

/// 网络地址只放在这里。每日数据更新后，App 会从该目录读取 index.json 和各期 JSON。
enum DigestConfig {
    static let baseURL = URL(string: "https://raw.githubusercontent.com/jincw1986-glitch/verseas-digest/main/data")!

    static func remoteURL(relativePath: String) -> URL {
        relativePath
            .split(separator: "/")
            .map(String.init)
            .reduce(baseURL) { url, part in
                url.appendingPathComponent(part)
            }
    }
}
