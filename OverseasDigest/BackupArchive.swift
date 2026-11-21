import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct OwlManifest: Codable, Sendable {
    var format: String
    var version: Int
    var images: [OwlImageRecord]

    static let formatName = "owlbackup"
    static let currentVersion = 1
}

struct OwlImageRecord: Codable, Sendable {
    var source: String
    var file: String
}

struct OwlBackupFile: FileDocument {
    static var readableContentTypes: [UTType] { [.zip] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else {
            throw BackupError.unreadable
        }
        data = contents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

enum BackupError: LocalizedError {
    case nothingToSave
    case unreadable
    case wrongFormat
    case tooLarge
    case unsupported

    var errorDescription: String? {
        switch self {
        case .nothingToSave:
            return "没有可以备份的简报。"
        case .unreadable:
            return "这个文件打不开。"
        case .wrongFormat:
            return "这不是猫头鹰的备份。"
        case .tooLarge:
            return "备份太大，无法打包。"
        case .unsupported:
            return "只能打开本应用导出的备份。"
        }
    }
}

@MainActor
final class BackupSession: ObservableObject {
    @Published var isWorking = false
    @Published var phase = ""
    @Published var completed = 0
    @Published var total = 0
    @Published var failedImages = 0
    @Published var status = ""
    @Published var exportFile: OwlBackupFile?
    @Published var showExporter = false
    @Published var showImporter = false

    private let repository: DigestRepository

    init(repository: DigestRepository = .shared) {
        self.repository = repository
    }

    func export() async {
        if isWorking { return }
        isWorking = true
        completed = 0
        total = 0
        failedImages = 0
        status = ""
        phase = "正在读取目录"
        defer { isWorking = false }
        do {
            let index = try await loadIndex()
            phase = "正在读取各期"
            var issueFiles: [String: Data] = [:]
            var pictures: [DigestPicture] = []
            var seenPictures = Set<String>()
            for entry in index.issues {
                phase = "正在读取 \(entry.date)"
                let issue: DigestIssue
                do {
                    issue = try await loadIssue(entry)
                } catch {
                    continue
                }
                guard let payload = repository.cachedIssueData(for: entry) else { continue }
                let name = entry.path.isEmpty ? "issues/\(entry.date).json" : entry.path
                issueFiles[name] = payload
                for picture in collectedPictures(in: issue) {
                    let key = picture.cacheKey
                    if key.isEmpty || seenPictures.contains(key) { continue }
                    seenPictures.insert(key)
                    pictures.append(picture)
                }
            }
            guard let indexData = repository.cachedIndexData() else { throw BackupError.nothingToSave }
            total = pictures.count
            var imagePayloads: [String: Data] = [:]
            var manifestImages: [OwlImageRecord] = []
            for picture in pictures {
                completed += 1
                let saved = await repository.acquireImageData(for: picture)
                if let saved {
                    let ext = repository.fileExtension(of: picture.path ?? picture.url ?? picture.cacheKey)
                    let file = "images/\(stableToken(picture.cacheKey)).\(ext)"
                    if imagePayloads[file] == nil {
                        imagePayloads[file] = saved
                    }
                    for key in repository.sourceKeys(for: picture) where !key.isEmpty {
                        manifestImages.append(OwlImageRecord(source: key, file: file))
                    }
                } else {
                    failedImages += 1
                }
                phase = "正在保存图片 \(completed)/\(total)，失败 \(failedImages)"
            }
            phase = "正在打包"
            var entries: [String: Data] = [:]
            entries["manifest.json"] = try JSONEncoder().encode(
                OwlManifest(format: OwlManifest.formatName, version: OwlManifest.currentVersion, images: manifestImages)
            )
            entries["index.json"] = indexData
            for (name, data) in issueFiles {
                entries[name] = data
            }
            for (name, data) in imagePayloads {
                entries[name] = data
            }
            let zip = try StoredZip.archive(entries)
            exportFile = OwlBackupFile(data: zip)
            if failedImages > 0 {
                status = "已打包。有 \(failedImages) 张图片没能下载，其余已放进备份。"
            } else if total == 0 {
                status = "已打包各期文字。这一份里没有图片。"
            } else {
                status = "已打包 \(index.issues.count) 期和 \(total) 张图片。"
            }
            showExporter = true
        } catch {
            status = error.localizedDescription
        }
    }

    func importFile(_ result: Result<URL, Error>, model: DigestModel) async {
        if isWorking { return }
        isWorking = true
        phase = "正在导入"
        status = ""
        defer { isWorking = false }
        do {
            let url = try result.get()
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let data = try Data(contentsOf: url)
            let summary = try restore(data)
            model.reloadFromDisk()
            status = summary
        } catch {
            status = error.localizedDescription
        }
    }

    func noteExport(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            break
        case .failure:
            status = "没有保存备份。"
        }
    }

    private func loadIndex() async throws -> IssueIndex {
        do {
            return try await repository.fetchIndex()
        } catch {
            guard let local = repository.loadIndex() else { throw BackupError.nothingToSave }
            return local
        }
    }

    private func loadIssue(_ entry: IndexEntry) async throws -> DigestIssue {
        do {
            return try await repository.fetchIssue(entry)
        } catch {
            guard let local = repository.loadIssue(entry) else { throw error }
            return local
        }
    }

    private func restore(_ data: Data) throws -> String {
        let files = try StoredZip.extract(data)
        guard let manifestData = files["manifest.json"] else { throw BackupError.wrongFormat }
        let manifest = try JSONDecoder().decode(OwlManifest.self, from: manifestData)
        guard manifest.format == OwlManifest.formatName, manifest.version == OwlManifest.currentVersion else {
            throw BackupError.wrongFormat
        }
        guard let indexData = files["index.json"] else { throw BackupError.wrongFormat }
        let imported = try JSONDecoder().decode(IssueIndex.self, from: indexData)
        var payloads: [String: Data] = [:]
        for (name, payload) in files where name.hasPrefix("issues/") && name.hasSuffix(".json") {
            payloads[name] = payload
        }
        let added = try repository.mergeImportedIssues(imported, payloads: payloads)
        var grouped: [String: [String]] = [:]
        for record in manifest.images where !record.source.isEmpty && !record.file.isEmpty {
            grouped[record.file, default: []].append(record.source)
        }
        var groups: [(keys: [String], data: Data)] = []
        for (file, keys) in grouped {
            guard let payload = files[file] else { continue }
            groups.append((keys, payload))
        }
        let stored = repository.storeImportedImages(groups)
        return "已并入 \(added) 期，保存了 \(stored) 张新图片。已有的期数不会重复添加。"
    }
}

private func collectedPictures(in issue: DigestIssue) -> [DigestPicture] {
    var list: [DigestPicture] = []
    for section in issue.sections {
        for item in section.items {
            if let image = item.image {
                list.append(image)
            }
        }
        if let image = section.photo?.image {
            list.append(image)
        }
        if let place = section.place {
            for photo in place.photos {
                list.append(photo.picture)
            }
        }
        for item in section.gallery {
            list.append(item.image)
        }
        if let wiki = section.wiki {
            list.append(contentsOf: wiki.images)
        }
    }
    return list
}

private func stableToken(_ string: String) -> String {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in string.utf8 {
        hash ^= UInt64(byte)
        hash &*= 1_099_511_628_211
    }
    return String(hash)
}

private enum StoredZip {
    static func archive(_ files: [String: Data]) throws -> Data {
        let names = files.keys.sorted().filter(isSafeZipName)
        var local = Data()
        var central = Data()
        for name in names {
            guard let payload = files[name] else { continue }
            let nameData = Data(name.utf8)
            if nameData.count > Int(UInt16.max) || payload.count > Int(UInt32.max) || local.count > Int(UInt32.max) {
                throw BackupError.tooLarge
            }
            let crc = CRC32.checksum(payload)
            let offset = UInt32(local.count)
            let size = UInt32(payload.count)
            local.append(contentsOf: [0x50, 0x4b, 0x03, 0x04] as [UInt8])
            appendU16(20, to: &local)
            appendU16(0x800, to: &local)
            appendU16(0, to: &local)
            appendU16(0, to: &local)
            appendU16(dosDate, to: &local)
            appendU32(crc, to: &local)
            appendU32(size, to: &local)
            appendU32(size, to: &local)
            appendU16(UInt16(nameData.count), to: &local)
            appendU16(0, to: &local)
            local.append(nameData)
            local.append(payload)

            central.append(contentsOf: [0x50, 0x4b, 0x01, 0x02] as [UInt8])
            appendU16(20, to: &central)
            appendU16(20, to: &central)
            appendU16(0x800, to: &central)
            appendU16(0, to: &central)
            appendU16(0, to: &central)
            appendU16(dosDate, to: &central)
            appendU32(crc, to: &central)
            appendU32(size, to: &central)
            appendU32(size, to: &central)
            appendU16(UInt16(nameData.count), to: &central)
            appendU16(0, to: &central)
            appendU16(0, to: &central)
            appendU16(0, to: &central)
            appendU16(0, to: &central)
            appendU32(0, to: &central)
            appendU32(offset, to: &central)
            central.append(nameData)
        }
        if central.count > Int(UInt32.max) || names.count > Int(UInt16.max) {
            throw BackupError.tooLarge
        }
        var output = local
        let centralOffset = UInt32(local.count)
        output.append(central)
        output.append(contentsOf: [0x50, 0x4b, 0x05, 0x06] as [UInt8])
        appendU16(0, to: &output)
        appendU16(0, to: &output)
        appendU16(UInt16(names.count), to: &output)
        appendU16(UInt16(names.count), to: &output)
        appendU32(UInt32(central.count), to: &output)
        appendU32(centralOffset, to: &output)
        appendU16(0, to: &output)
        return output
    }

    static func extract(_ data: Data) throws -> [String: Data] {
        guard let eocd = findEOCD(data) else { throw BackupError.unreadable }
        let count = Int(readU16(data, eocd + 10))
        let centralSize = Int(readU32(data, eocd + 12))
        let centralOffset = Int(readU32(data, eocd + 16))
        guard centralOffset >= 0, centralSize >= 0, centralOffset + centralSize <= data.count else {
            throw BackupError.unreadable
        }
        var cursor = centralOffset
        let end = centralOffset + centralSize
        var files: [String: Data] = [:]
        for _ in 0..<count {
            guard cursor + 46 <= end, readU32(data, cursor) == 0x02014b50 else { throw BackupError.unreadable }
            let method = readU16(data, cursor + 10)
            let compressed = Int(readU32(data, cursor + 20))
            let nameLength = Int(readU16(data, cursor + 28))
            let extraLength = Int(readU16(data, cursor + 30))
            let commentLength = Int(readU16(data, cursor + 32))
            let localOffset = Int(readU32(data, cursor + 42))
            let nameStart = cursor + 46
            let nameEnd = nameStart + nameLength
            guard nameEnd <= end else { throw BackupError.unreadable }
            let nameData = data.subdata(in: nameStart..<nameEnd)
            guard let name = String(data: nameData, encoding: .utf8), isSafeZipName(name) else {
                throw BackupError.unreadable
            }
            if method != 0 {
                throw BackupError.unsupported
            }
            let payload = try readStoredFile(data, localOffset: localOffset, expectedCount: compressed)
            files[name] = payload
            cursor = nameEnd + extraLength + commentLength
        }
        return files
    }

    private static let dosDate: UInt16 = (46 << 9) | (11 << 5) | 21

    private static func readStoredFile(_ data: Data, localOffset: Int, expectedCount: Int) throws -> Data {
        guard localOffset >= 0, localOffset + 30 <= data.count, readU32(data, localOffset) == 0x04034b50 else {
            throw BackupError.unreadable
        }
        let nameLength = Int(readU16(data, localOffset + 26))
        let extraLength = Int(readU16(data, localOffset + 28))
        let start = localOffset + 30 + nameLength + extraLength
        let end = start + expectedCount
        guard start >= 0, end <= data.count else { throw BackupError.unreadable }
        return data.subdata(in: start..<end)
    }

    private static func findEOCD(_ data: Data) -> Int? {
        let minimum = 22
        guard data.count >= minimum else { return nil }
        let window = min(data.count, minimum + 65535)
        var index = data.count - minimum
        let limit = data.count - window
        while index >= limit {
            if readU32(data, index) == 0x06054b50 {
                return index
            }
            if index == 0 { break }
            index -= 1
        }
        return nil
    }
}

private enum CRC32 {
    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffff_ffff
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xff)
            crc = table[index] ^ (crc >> 8)
        }
        return crc ^ 0xffff_ffff
    }

    private static let table: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 {
            if crc & 1 == 1 {
                crc = 0xedb8_8320 ^ (crc >> 1)
            } else {
                crc >>= 1
            }
        }
        return crc
    }
}

private func isSafeZipName(_ name: String) -> Bool {
    if name.isEmpty || name.hasPrefix("/") || name.hasPrefix("\\") { return false }
    if name.contains("..") || name.contains("\\") { return false }
    return true
}

private func appendU16(_ value: UInt16, to data: inout Data) {
    data.append(UInt8(value & 0xff))
    data.append(UInt8((value >> 8) & 0xff))
}

private func appendU32(_ value: UInt32, to data: inout Data) {
    data.append(UInt8(value & 0xff))
    data.append(UInt8((value >> 8) & 0xff))
    data.append(UInt8((value >> 16) & 0xff))
    data.append(UInt8((value >> 24) & 0xff))
}

private func readU16(_ data: Data, _ offset: Int) -> UInt16 {
    guard offset >= 0, offset + 1 < data.count else { return 0 }
    return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
}

private func readU32(_ data: Data, _ offset: Int) -> UInt32 {
    guard offset >= 0, offset + 3 < data.count else { return 0 }
    return UInt32(data[offset])
        | (UInt32(data[offset + 1]) << 8)
        | (UInt32(data[offset + 2]) << 16)
        | (UInt32(data[offset + 3]) << 24)
}
