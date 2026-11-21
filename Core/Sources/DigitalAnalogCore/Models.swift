import Foundation

/// Title/artist/album hints used to look up metadata and cover art for a
/// record in the user's library. It never refers to an online media source.
public struct Recording: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var artist: String
    public var duration: Double?
    public var album: String?
    public var year: Int?
    public init(id: String, title: String, artist: String, duration: Double? = nil, album: String? = nil, year: Int? = nil) {
        self.id = id; self.title = title; self.artist = artist; self.duration = duration; self.album = album; self.year = year
    }
}
public struct Track: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var artist: String
    public var album: String
    public var file: String
    public var artwork: String?
    public var duration: Double
    public var favorite: Bool
    public var added: Date
    public var lastPlayed: Date?
    public var digest: String
    public var year: Int?
    public var genre: String?
    public var sourceID: String?
    public var releaseID: String?
    public var artworkSource: String?
    public var lyrics: String?
    public init(id: UUID = UUID(), title: String, artist: String = "Unknown artist", album: String = "Singles", file: String, artwork: String? = nil, duration: Double = 0, favorite: Bool = false, added: Date = Date(), lastPlayed: Date? = nil, digest: String, year: Int? = nil, genre: String? = nil, sourceID: String? = nil, releaseID: String? = nil, artworkSource: String? = nil, lyrics: String? = nil) {
        self.id=id; self.title=title; self.artist=artist; self.album=album; self.file=file; self.artwork=artwork; self.duration=duration; self.favorite=favorite; self.added=added; self.lastPlayed=lastPlayed; self.digest=digest; self.year=year; self.genre=genre; self.sourceID=sourceID; self.releaseID=releaseID; self.artworkSource=artworkSource; self.lyrics=lyrics
    }
    public var albumKey: String {
        if let releaseID { return "mb:\(releaseID)" }
        if album == "Singles" || album.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return id.uuidString }
        return MetadataMatcher.normalized(artist) + "|" + MetadataMatcher.normalized(album)
    }
}
public struct Playlist: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var tracks: [UUID]
    public var created: Date
    public init(id: UUID = UUID(), name: String, tracks: [UUID] = [], created: Date = Date()) { self.id=id; self.name=name; self.tracks=tracks; self.created=created }
}
public enum LibraryError: Error, LocalizedError, Equatable {
    case database(String), invalidName, missingTrack, invalidOrder, unsafePath, corruptData
    public var errorDescription: String? {
        switch self {
        case .database(let s): return "Collection storage: \(s)"
        case .invalidName: return "Enter a name."
        case .missingTrack: return "This record is no longer in the collection."
        case .invalidOrder: return "The new order must contain each existing item once."
        case .unsafePath: return "An invalid media path was rejected."
        case .corruptData: return "The saved collection could not be read."
        }
    }
}
public enum MediaPaths {
    public static func file(_ name: String, under root: URL) throws -> URL {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\\"), !name.contains("\0") else { throw LibraryError.unsafePath }
        return root.appendingPathComponent(name)
    }
}
