import Foundation

/// Matches from the user's own library. Albums are identified by `Track.albumKey`.
public struct LibrarySearchResults: Equatable, Sendable {
    public var tracks: [Track]
    public var albums: [String]
    public var artists: [String]
    public var playlists: [Playlist]
    public init(tracks: [Track] = [], albums: [String] = [], artists: [String] = [], playlists: [Playlist] = []) {
        self.tracks=tracks; self.albums=albums; self.artists=artists; self.playlists=playlists
    }
    public var isEmpty: Bool { tracks.isEmpty && albums.isEmpty && artists.isEmpty && playlists.isEmpty }
}

/// Offline, case- and diacritic-insensitive search over imported records and playlists.
/// Every word of the query must appear; nothing leaves the device.
public enum LibrarySearch {
    public static func terms(_ query: String) -> [String] {
        MetadataMatcher.normalized(query).split(separator: " ").map(String.init)
    }
    public static func matches(_ text: String, terms needles: [String]) -> Bool {
        guard !needles.isEmpty else { return false }
        let haystack = MetadataMatcher.normalized(text)
        return needles.allSatisfy { haystack.contains($0) }
    }
    public static func search(_ query: String, tracks: [Track], playlists: [Playlist]) -> LibrarySearchResults {
        let needles = terms(query)
        guard !needles.isEmpty else { return LibrarySearchResults() }
        let phrase = needles.joined(separator: " ")
        var songs: [(rank: Int, track: Track)] = []
        var albums: [String] = []; var seenAlbums = Set<String>()
        var artists: [String] = []; var seenArtists = Set<String>()
        for track in tracks {
            let album = track.album.trimmingCharacters(in: .whitespacesAndNewlines)
            // "Singles" is a placeholder, not a real album name, so it is not searchable.
            let albumText = album == "Singles" ? "" : album
            if matches("\(track.title) \(track.artist) \(albumText) \(track.genre ?? "")", terms: needles) {
                let rank = MetadataMatcher.normalized(track.title).hasPrefix(phrase) ? 0 : matches(track.title, terms: needles) ? 1 : 2
                songs.append((rank: rank, track: track))
            }
            if !albumText.isEmpty, matches("\(albumText) \(track.artist)", terms: needles), seenAlbums.insert(track.albumKey).inserted {
                albums.append(track.albumKey)
            }
            let artist = MetadataMatcher.normalized(track.artist)
            if !artist.isEmpty, matches(track.artist, terms: needles), seenArtists.insert(artist).inserted {
                artists.append(track.artist)
            }
        }
        // Title matches first; otherwise keep the library's own order.
        let ranked = songs.enumerated().sorted { a, b in
            a.element.rank != b.element.rank ? a.element.rank < b.element.rank : a.offset < b.offset
        }.map { $0.element.track }
        return LibrarySearchResults(tracks: ranked, albums: albums, artists: artists, playlists: playlists.filter { matches($0.name, terms: needles) })
    }
    /// All records credited to an artist, compared the same way search compares names.
    public static func tracks(byArtist name: String, in tracks: [Track]) -> [Track] {
        let key = MetadataMatcher.normalized(name)
        return tracks.filter { MetadataMatcher.normalized($0.artist) == key }
    }
}
