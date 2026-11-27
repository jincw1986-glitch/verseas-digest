import Foundation

struct IssueIndex: Codable, Equatable {
    var issues: [IndexEntry]
}

struct IndexEntry: Codable, Hashable, Identifiable, Sendable {
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

    var readingSections: [DigestSection] { sections.filter { $0.name != "每日一图" } }
}

struct DigestSection: Codable, Equatable, Identifiable {
    var id: String { name }
    var name: String
    var displayName: String { Self.displayName(for: name) }
    var items: [DigestItem]
    var jokes: [JokeItem]
    var photo: PhotoOfDay?
    var place: PlaceEssay?
    var gallery: [GalleryItem]
    var wiki: WikiArticle?

    static func displayName(for name: String) -> String {
        name == "笑话" ? "段子" : name
    }

    var importanceCounts: [NewsImportance: Int] {
        items.reduce(into: [:]) { counts, item in
            if let level = item.importance {
                counts[level, default: 0] += 1
            }
        }
    }

    var entryCount: Int {
        switch name {
        case "笑话": return jokes.count
        case "每日一图": return photo == nil ? 0 : 1
        case "天涯海角": return place == nil ? 0 : 1
        case "美女与野兽": return gallery.count
        case "维基漫游": return wiki == nil ? 0 : 1
        default: return items.count
        }
    }

    private enum CodingKeys: String, CodingKey {
        case name, items, photo, place, gallery, wiki
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        items = []
        jokes = []
        photo = nil
        place = nil
        gallery = []
        wiki = nil
        switch name {
        case "笑话":
            jokes = try container.decode([JokeItem].self, forKey: .items)
        case "每日一图":
            photo = try container.decode(PhotoOfDay.self, forKey: .photo)
        case "天涯海角":
            place = try container.decode(PlaceEssay.self, forKey: .place)
        case "美女与野兽":
            gallery = try container.decode([GalleryItem].self, forKey: .gallery)
        case "维基漫游":
            wiki = try container.decode(WikiArticle.self, forKey: .wiki)
        default:
            items = try container.decode([DigestItem].self, forKey: .items)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        switch name {
        case "笑话":
            try container.encode(jokes, forKey: .items)
        case "每日一图":
            try container.encode(photo, forKey: .photo)
        case "天涯海角":
            try container.encode(place, forKey: .place)
        case "美女与野兽":
            try container.encode(gallery, forKey: .gallery)
        case "维基漫游":
            try container.encode(wiki, forKey: .wiki)
        default:
            try container.encode(items, forKey: .items)
        }
    }
}

struct WikiArticle: Codable, Equatable {
    var title: String
    var originalTitle: String
    var tagline: String
    var body: String
    var images: [DigestPicture]
    var sourceUrl: String

    var webURL: URL? {
        guard let url = URL(string: sourceUrl), url.scheme == "https" else { return nil }
        return url
    }
}

struct PhotoOfDay: Codable, Equatable {
    var title: String
    var interpretation: String
    var image: DigestPicture
    var sources: [SourceLink]
}

struct PlacePhoto: Codable, Equatable, Identifiable {
    var id: String { path ?? url ?? credit }
    var path: String?
    var url: String?
    var credit: String
    var caption: String?

    var picture: DigestPicture {
        DigestPicture(path: path, url: url, credit: credit)
    }
}

struct PlaceEssay: Codable, Equatable {
    var name: String
    var paragraphs: [String]
    var photos: [PlacePhoto]
}

struct GalleryItem: Codable, Equatable, Identifiable {
    var id: String { caption }
    var kind: String
    var caption: String
    var image: DigestPicture
    var source: SourceLink?

    var kindLabel: String { kind == "animal" ? "动物" : "人物" }
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
    var importance: NewsImportance? = nil
}

enum NewsImportance: String, Codable, CaseIterable, Hashable {
    case major, notable, routine

    var label: String {
        switch self {
        case .major: "重大"
        case .notable: "重点"
        case .routine: "常规"
        }
    }

    var rank: Int {
        switch self {
        case .major: 3
        case .notable: 2
        case .routine: 1
        }
    }
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

struct DigestPicture: Codable, Equatable, Sendable {
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
