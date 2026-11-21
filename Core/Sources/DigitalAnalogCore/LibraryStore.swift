import Foundation
import CSQLite

private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
private final class Database: @unchecked Sendable {
    var handle: OpaquePointer?
    init(_ url: URL) throws {
        guard sqlite3_open_v2(url.path,&handle,SQLITE_OPEN_READWRITE|SQLITE_OPEN_CREATE|SQLITE_OPEN_FULLMUTEX,nil)==SQLITE_OK else { throw LibraryError.database("Cannot open database") }
        sqlite3_busy_timeout(handle,5000)
        try execute("PRAGMA foreign_keys=ON"); try execute("PRAGMA journal_mode=WAL"); try execute("PRAGMA synchronous=FULL")
    }
    deinit { sqlite3_close(handle) }
    func execute(_ sql: String, _ values: [String?] = []) throws {
        let statement=try prepare(sql,values); defer { sqlite3_finalize(statement) }
        let result=sqlite3_step(statement)
        guard result==SQLITE_DONE || result==SQLITE_ROW else { throw failure() }
    }
    func rows(_ sql: String,_ values: [String?] = []) throws -> [[String]] {
        let statement=try prepare(sql,values); defer { sqlite3_finalize(statement) }; var rows=[[String]]()
        while true {
            let status=sqlite3_step(statement); if status==SQLITE_DONE { return rows }; guard status==SQLITE_ROW else { throw failure() }
            rows.append((0..<sqlite3_column_count(statement)).map { i in
                if sqlite3_column_type(statement,i)==SQLITE_FLOAT { return String(sqlite3_column_double(statement,i)) }
                return sqlite3_column_text(statement,i).map { String(cString:$0) } ?? ""
            })
        }
    }
    private func prepare(_ sql: String,_ values: [String?]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle,sql,-1,&statement,nil)==SQLITE_OK, let statement else { throw failure() }
        for (i,value) in values.enumerated() {
            let status: Int32
            if let value { status=sqlite3_bind_text(statement,Int32(i+1),value,-1,transient) } else { status=sqlite3_bind_null(statement,Int32(i+1)) }
            if status != SQLITE_OK { sqlite3_finalize(statement); throw failure() }
        }
        return statement
    }
    func failure() -> LibraryError { .database(String(cString:sqlite3_errmsg(handle))) }
    func transaction<T>(_ work: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do { let result=try work(); try execute("COMMIT"); return result } catch { try? execute("ROLLBACK"); throw error }
    }
}

public struct LibrarySnapshot: Sendable {
    public var tracks: [Track]
    public var playlists: [Playlist]
    public var queue: QueueState
}
public actor LibraryStore {
    private let db: Database
    private let encoder=JSONEncoder()
    private let decoder=JSONDecoder()
    public init(url: URL) throws {
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        db=try Database(url)
        try db.transaction {
            try db.execute("CREATE TABLE IF NOT EXISTS tracks(id TEXT PRIMARY KEY, digest TEXT NOT NULL UNIQUE, source TEXT UNIQUE, payload TEXT NOT NULL)")
            try db.execute("CREATE TABLE IF NOT EXISTS playlists(id TEXT PRIMARY KEY, name TEXT NOT NULL, created REAL NOT NULL, position INTEGER NOT NULL)")
            try db.execute("CREATE TABLE IF NOT EXISTS playlist_tracks(playlist TEXT NOT NULL REFERENCES playlists(id) ON DELETE CASCADE, track TEXT NOT NULL REFERENCES tracks(id) ON DELETE CASCADE, position INTEGER NOT NULL, PRIMARY KEY(playlist,track))")
            try db.execute("CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, payload TEXT NOT NULL)")
            try db.execute("PRAGMA user_version=1")
        }
    }
    private func json<T: Encodable>(_ value: T) throws -> String { String(decoding:try encoder.encode(value),as:UTF8.self) }
    private func decode<T: Decodable>(_ type:T.Type,_ value:String) throws -> T { try decoder.decode(type,from:Data(value.utf8)) }
    public func tracks() throws -> [Track] { try db.rows("SELECT payload FROM tracks ORDER BY rowid DESC").map { try decode(Track.self,$0[0]) } }
    public func track(id: UUID) throws -> Track? { try db.rows("SELECT payload FROM tracks WHERE id=?",[id.uuidString]).first.map { try decode(Track.self,$0[0]) } }
    public func track(source: String) throws -> Track? { try db.rows("SELECT payload FROM tracks WHERE source=?",[source]).first.map { try decode(Track.self,$0[0]) } }
    public func existing(digest:String,source:String?=nil) throws -> Track? {
        try db.rows("SELECT payload FROM tracks WHERE digest=? OR (source IS NOT NULL AND source=?) LIMIT 1",[digest,source]).first.map { try decode(Track.self,$0[0]) }
    }
    public func snapshot() throws -> LibrarySnapshot { try LibrarySnapshot(tracks:tracks(),playlists:playlists(),queue:queue()) }
    /// Returns an existing identity for exact-file/source duplicates. Never overwrites its edits.
    @discardableResult public func insert(_ track: Track) throws -> Track {
        _ = try MediaPaths.file(track.file,under:URL(fileURLWithPath:"/media"))
        if let name=track.artwork { _ = try MediaPaths.file(name,under:URL(fileURLWithPath:"/art")) }
        if let existing=try db.rows("SELECT payload FROM tracks WHERE digest=? OR (source IS NOT NULL AND source=?) LIMIT 1",[track.digest,track.sourceID]).first { return try decode(Track.self,existing[0]) }
        try db.execute("INSERT INTO tracks(id,digest,source,payload) VALUES(?,?,?,?)",[track.id.uuidString,track.digest,track.sourceID,try json(track)])
        return track
    }
    public func update(_ track: Track) throws {
        guard try self.track(id:track.id) != nil else { throw LibraryError.missingTrack }
        _ = try MediaPaths.file(track.file,under:URL(fileURLWithPath:"/media"))
        if let name=track.artwork { _ = try MediaPaths.file(name,under:URL(fileURLWithPath:"/art")) }
        try db.execute("UPDATE tracks SET digest=?,source=?,payload=? WHERE id=?",[track.digest,track.sourceID,try json(track),track.id.uuidString])
    }
    public func deleteTrack(_ id: UUID) throws {
        try db.transaction {
            try db.execute("DELETE FROM tracks WHERE id=?",[id.uuidString])
            var q=try queue(); q.remove(id); try saveQueue(q)
        }
    }
    public func playlists() throws -> [Playlist] {
        try db.rows("SELECT id,name,created FROM playlists ORDER BY position").map { row in
            guard let id=UUID(uuidString:row[0]), let seconds=Double(row[2]) else { throw LibraryError.corruptData }
            let ids=try db.rows("SELECT track FROM playlist_tracks WHERE playlist=? ORDER BY position",[row[0]]).compactMap { UUID(uuidString:$0[0]) }
            return Playlist(id:id,name:row[1],tracks:ids,created:Date(timeIntervalSinceReferenceDate:seconds))
        }
    }
    public func createPlaylist(_ name: String) throws -> Playlist {
        let clean=name.trimmingCharacters(in:.whitespacesAndNewlines); guard !clean.isEmpty else { throw LibraryError.invalidName }
        let list=Playlist(name:clean)
        try db.execute("INSERT INTO playlists VALUES(?,?,?,(SELECT COALESCE(MAX(position),-1)+1 FROM playlists))",[list.id.uuidString,list.name,String(list.created.timeIntervalSinceReferenceDate)])
        return list
    }
    public func renamePlaylist(_ id: UUID, name: String) throws {
        let clean=name.trimmingCharacters(in:.whitespacesAndNewlines); guard !clean.isEmpty else { throw LibraryError.invalidName }
        try db.execute("UPDATE playlists SET name=? WHERE id=?",[clean,id.uuidString])
    }
    public func deletePlaylist(_ id: UUID) throws { try db.execute("DELETE FROM playlists WHERE id=?",[id.uuidString]) }
    public func add(_ track: UUID, to playlist: UUID) throws {
        try db.execute("INSERT OR IGNORE INTO playlist_tracks(playlist,track,position) VALUES(?,?,(SELECT COALESCE(MAX(position),-1)+1 FROM playlist_tracks WHERE playlist=?))",[playlist.uuidString,track.uuidString,playlist.uuidString])
    }
    public func remove(_ track: UUID, from playlist: UUID) throws { try db.execute("DELETE FROM playlist_tracks WHERE playlist=? AND track=?",[playlist.uuidString,track.uuidString]) }
    public func reorderPlaylist(_ id: UUID, tracks: [UUID]) throws {
        let old=try db.rows("SELECT track FROM playlist_tracks WHERE playlist=?",[id.uuidString]).compactMap { UUID(uuidString:$0[0]) }
        guard Set(old)==Set(tracks),old.count==tracks.count else { throw LibraryError.invalidOrder }
        try db.transaction { for (i,t) in tracks.enumerated() { try db.execute("UPDATE playlist_tracks SET position=? WHERE playlist=? AND track=?",[String(i),id.uuidString,t.uuidString]) } }
    }
    public func reorderPlaylists(_ order: [UUID]) throws {
        let old=try playlists().map(\.id); guard Set(old)==Set(order),old.count==order.count else { throw LibraryError.invalidOrder }
        try db.transaction { for (i,id) in order.enumerated() { try db.execute("UPDATE playlists SET position=? WHERE id=?",[String(i),id.uuidString]) } }
    }
    public func queue() throws -> QueueState { try db.rows("SELECT payload FROM settings WHERE key='queue'").first.map { try decode(QueueState.self,$0[0]) } ?? QueueState() }
    public func saveQueue(_ queue: QueueState) throws { try Task.checkCancellation(); try db.execute("INSERT INTO settings VALUES('queue',?) ON CONFLICT(key) DO UPDATE SET payload=excluded.payload",[try json(queue)]) }
    public func integrityCheck() throws -> Bool { try db.rows("PRAGMA integrity_check").first?.first == "ok" && db.rows("PRAGMA foreign_key_check").isEmpty }
    public func restore(tracks: [Track], playlists: [Playlist]) throws {
        try db.transaction {
            var identities=[UUID:UUID]()
            for track in tracks { let actual=try insert(track); identities[track.id]=actual.id }
            for list in playlists {
                guard !list.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { throw LibraryError.invalidName }
                if try db.rows("SELECT id FROM playlists WHERE id=?",[list.id.uuidString]).isEmpty {
                    try db.execute("INSERT INTO playlists VALUES(?,?,?,(SELECT COALESCE(MAX(position),-1)+1 FROM playlists))",[list.id.uuidString,list.name,String(list.created.timeIntervalSinceReferenceDate)])
                    for id in list.tracks {
                        guard let mapped=identities[id] else { throw LibraryError.missingTrack }
                        try add(mapped,to:list.id)
                    }
                }
            }
        }
    }
    public func checkpoint() throws { try db.execute("PRAGMA wal_checkpoint(FULL)") }
    public func backupSnapshot() throws -> (snapshot:LibrarySnapshot,manifest:Data) {
        struct Export:Codable { var schema=1; var tracks:[Track]; var playlists:[Playlist]; var queue:QueueState }
        let value=try snapshot()
        let bytes=try encoder.encode(Export(tracks:value.tracks,playlists:value.playlists,queue:value.queue))
        return (value,bytes)
    }
    public func exportSnapshot() throws -> Data { try backupSnapshot().manifest }
}
