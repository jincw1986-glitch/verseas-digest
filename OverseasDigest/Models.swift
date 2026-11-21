import Foundation

struct IssueIndex: Codable, Equatable {
    var issues: [IndexEntry]
}

struct IndexEntry: Codable, Equatable, Identifiable {
    var id: String { date }
    var date: String
    var title: String
    var path: String
}

struct DigestIssue: Codable, Equatable, Identifiable {
    var id: String { date }
    var date: String
    var title: String
    var sections: [DigestSection]
}

struct DigestSection: Codable, Equatable, Identifiable {
    var id: String { name }
    var name: String
    var items: [DigestItem]
    var jokes: [JokeItem]

    var entryCount: Int { name == "笑话" ? jokes.count : items.count }

    private enum CodingKeys: String, CodingKey {
        case name
        case items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        if name == "笑话" {
            jokes = try container.decode([JokeItem].self, forKey: .items)
            items = []
        } else {
            items = try container.decode([DigestItem].self, forKey: .items)
            jokes = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        if name == "笑话" {
            try container.encode(jokes, forKey: .items)
        } else {
            try container.encode(items, forKey: .items)
        }
    }
}

struct JokeItem: Codable, Equatable, Identifiable {
    var id: String { url }
    var text: String
    var translation: String?
    var authorName: String
    var handle: String
    var url: String
    var note: String?

    var postURL: URL? {
        guard let url = URL(string: url), url.scheme == "https" else { return nil }
        return url
    }
}

struct DigestItem: Codable, Equatable, Identifiable {
    var id: String { headline }
    var headline: String
    var summary: String
    var sources: [SourceLink]
    var image: DigestPicture?
    var glossary: [GlossaryEntry]
}

struct SourceLink: Codable, Equatable, Identifiable {
    var id: String { url }
    var name: String
    var url: String

    var webURL: URL? {
        guard let url = URL(string: url), url.scheme == "https" else { return nil }
        return url
    }
}

struct DigestPicture: Codable, Equatable {
    var path: String?
    var url: String?
    var credit: String

    var cacheKey: String { path ?? url ?? credit }
}

struct GlossaryEntry: Codable, Equatable, Identifiable {
    var id: String { term }
    var term: String
    var type: GlossaryType
    var explanation: String
}

enum GlossaryType: String, Codable, Equatable {
    case person
    case term
    case concept
    case award
    case org

    var label: String {
        switch self {
        case .person: "人物"
        case .term: "术语"
        case .concept: "概念"
        case .award: "奖项"
        case .org: "机构"
        }
    }
}

enum ChineseDate {
    static func string(from iso: String) -> String {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return iso }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        components.calendar = calendar
        guard let date = calendar.date(from: components) else { return iso }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = calendar
        formatter.setLocalizedDateFormatFromTemplate("yMMMMdEEEE")
        return formatter.string(from: date)
    }
}
