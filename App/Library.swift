import SwiftUI
import AVFoundation
import CryptoKit
import DigitalAnalogCore

@MainActor final class Library: ObservableObject {
    @Published private(set) var catalog=Catalog()
    @Published var error:String?
    @Published private(set) var loading=true
    @Published private(set) var importing=false
    @Published private(set) var ready=false
    private(set) var store:LibraryStore?
    init() {}
    func start() async {
        defer { loading=false }
        do {
            if store==nil { store=try await Task.detached(priority:.userInitiated) { try LibraryStore(url:Disk.root.appendingPathComponent("collection.sqlite")) }.value }
            guard let store else { return }
            try await migrateLegacyIfNeeded(store)
            try await refresh(); ready=true
        } catch { self.error="Cannot open the collection. Your files have not been deleted. \(error.localizedDescription)" }
    }
    func refresh() async throws {
        guard let store else { throw AppFailure.message("Collection storage is unavailable") }
        let snapshot=try await store.snapshot()
        catalog=Catalog(tracks:snapshot.tracks,playlists:snapshot.playlists)
    }
    func perform(_ operation:@escaping @Sendable (LibraryStore) async throws -> Void) {
        guard let store else { return }
        Task { do { try await operation(store); try await refresh() } catch { self.error=error.localizedDescription } }
    }
    func update(_ track:Track) { perform { try await $0.update(track) } }
    func toggleFavorite(_ id:UUID) {
        perform { store in guard var t=try await store.track(id:id) else { return }; t.favorite.toggle(); try await store.update(t) }
    }
    func createPlaylist(_ name:String) { perform { _=try await $0.createPlaylist(name) } }
    func renamePlaylist(_ id:UUID,name:String) { perform { try await $0.renamePlaylist(id,name:name) } }
    func deletePlaylist(_ id:UUID) { perform { try await $0.deletePlaylist(id) } }
    func reorderPlaylists(_ ids:[UUID]) { perform { try await $0.reorderPlaylists(ids) } }
    func reorderPlaylist(_ id:UUID,tracks:[UUID]) { perform { try await $0.reorderPlaylist(id,tracks:tracks) } }
    func addToPlaylist(_ id:UUID,playlist:UUID) { perform { try await $0.add(id,to:playlist) } }
    func removeFromPlaylist(_ id:UUID,playlist:UUID) { perform { try await $0.remove(id,from:playlist) } }
    func removeTrack(_ track:Track) {
        perform { store in
            try await store.deleteTrack(track.id)
            try? FileManager.default.removeItem(at:Disk.audio(track.file))
            if let art=track.artwork,!(try await store.tracks()).contains(where:{ $0.artwork==art }) { try? FileManager.default.removeItem(at:Disk.art(art)) }
        }
    }
    func add(_ urls:[URL]) async {
        guard ready else { return }; importing=true; defer { importing=false }
        for url in urls {
            let access=url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
            do { _=try await ingest(url) } catch { self.error="Could not import \(url.lastPathComponent): \(error.localizedDescription)" }
        }
    }
    /// `recording` optionally supplies known title/artist/album hints (used by fixtures and tests).
    @discardableResult func ingest(_ url:URL,recording:Recording?=nil,artwork:ArtworkResolution?=nil) async throws -> Track {
        guard let store else { throw AppFailure.message("Collection storage is unavailable") }
        let asset=AVURLAsset(url:url)
        guard try await asset.load(.isPlayable), !(try await asset.load(.hasProtectedContent)), !(try await asset.loadTracks(withMediaType:.audio)).isEmpty else { throw AppFailure.message("This file does not contain playable, unprotected audio.") }
        let duration=try await asset.load(.duration).seconds
        guard duration.isFinite,duration>0 else { throw AppFailure.message("The audio duration is invalid.") }
        let digest=try await Task.detached(priority:.utility) {
            let input=try FileHandle(forReadingFrom:url); defer { try? input.close() }; var hash=SHA256()
            while let data=try input.read(upToCount:1_048_576),!data.isEmpty { hash.update(data:data) }
            return hash.finalize().map { String(format:"%02x",$0) }.joined()
        }.value
        if let existing=try await store.existing(digest:digest,source:recording?.id) {
            try await refresh(); return existing
        }
        var track=Track(id:UUID(),title:recording?.title ?? url.deletingPathExtension().lastPathComponent,artist:recording?.artist ?? "Unknown artist",album:recording?.album ?? "Singles",file:digest+"."+url.pathExtension.lowercased(),duration:duration,digest:digest,year:recording?.year,sourceID:recording?.id)
        for item in try await asset.load(.commonMetadata) {
            switch item.commonKey {
            case .commonKeyTitle: if let value=try? await item.load(.stringValue),!value.isEmpty { track.title=value }
            case .commonKeyArtist: if let value=try? await item.load(.stringValue),!value.isEmpty { track.artist=value }
            case .commonKeyAlbumName: if let value=try? await item.load(.stringValue),!value.isEmpty { track.album=value }
            case .commonKeyArtwork: if let bytes=try? await item.load(.dataValue),let name=try? await ArtworkFiles.store(bytes,key:digest) { track.artwork=name; track.artworkSource="Embedded in audio file" }
            default: break
            }
        }
        var artwork=artwork
        if track.artwork==nil,artwork==nil,track.artist != "Unknown artist" {
            let source=recording ?? Recording(id:"local",title:track.title,artist:track.artist,duration:track.duration,album:track.album)
            artwork=await ArtworkService.shared.resolve(source,key:UUID().uuidString)
        }
        if let artwork {
            if let match=artwork.match { track.title=match.title; track.artist=match.artist; track.album=match.album ?? track.album; track.releaseID=match.releaseID; track.year=match.year ?? track.year }
            if track.artwork == nil { track.artwork=artwork.file; track.artworkSource=artwork.provenance }
        }
        if track.artwork == nil { track.artwork=try await ArtworkFiles.generated(track); track.artworkSource="Generated on this iPhone" }
        let destination=Disk.audio(track.file)
        try await Task.detached(priority:.utility) {
            if !FileManager.default.fileExists(atPath:destination.path) {
                let temporary=destination.appendingPathExtension("installing")
                try? FileManager.default.removeItem(at:temporary)
                try FileManager.default.copyItem(at:url,to:temporary)
                try FileManager.default.setAttributes([.protectionKey:FileProtectionType.completeUntilFirstUserAuthentication],ofItemAtPath:temporary.path)
                let file=try FileHandle(forWritingTo:temporary); try file.synchronize(); try file.close()
                try FileManager.default.moveItem(at:temporary,to:destination)
            }
        }.value
        try Task.checkCancellation()
        let saved=try await store.insert(track)
        try await refresh(); return saved
    }
    /// Upgrade old generated covers in place; existing real/manual artwork stays intact.
    func recoverArtwork() async throws -> Int {
        guard let store else { return 0 }; var count=0
        for var track in catalog.tracks where track.artwork==nil || track.artworkSource?.hasPrefix("Generated")==true {
            try Task.checkCancellation()
            let source=Recording(id:track.sourceID ?? "local",title:track.title,artist:track.artist,duration:track.duration,album:track.album=="Singles" ? nil:track.album)
            let resolution=await ArtworkService.shared.resolve(source,key:UUID().uuidString)
            guard let file=resolution.file else { continue }
            // Read the latest row so a concurrent favorite/edit is never overwritten.
            guard let current=try await store.track(id:track.id),current.artwork==track.artwork,current.title==track.title,current.artist==track.artist,current.sourceID==track.sourceID else { continue }
            track=current; track.artwork=file; track.artworkSource=resolution.provenance
            try await store.update(track); count += 1; try await refresh()
        }
        return count
    }
    func export() async throws -> URL {
        guard let store else { throw AppFailure.message("Storage unavailable") }
        let folder=Disk.root.appendingPathComponent("Exports").appendingPathComponent("DigitalAnalog-"+UUID().uuidString+".digitalanalog",isDirectory:true)
        let media=folder.appendingPathComponent("Audio"),arts=folder.appendingPathComponent("Artwork")
        try FileManager.default.createDirectory(at:media,withIntermediateDirectories:true)
        try FileManager.default.createDirectory(at:arts,withIntermediateDirectories:true)
        let backup=try await store.backupSnapshot(); let snapshot=backup.snapshot; let manifest=backup.manifest
        try await Task.detached(priority:.utility) {
            try manifest.write(to:folder.appendingPathComponent("collection.json"),options:.atomic)
            for track in snapshot.tracks {
                let dst=media.appendingPathComponent(track.file)
                if !FileManager.default.fileExists(atPath:dst.path) { try FileManager.default.copyItem(at:Disk.audio(track.file),to:dst) }
                if let name=track.artwork { let dst=arts.appendingPathComponent(name); if !FileManager.default.fileExists(atPath:dst.path) { try FileManager.default.copyItem(at:Disk.art(name),to:dst) } }
            }
        }.value
        return folder
    }
    func restoreBackup(_ folder:URL) async throws {
        guard let store else { throw AppFailure.message("Collection unavailable") }
        struct Backup:Decodable { var schema:Int; var tracks:[Track]; var playlists:[Playlist] }
        let backup=try JSONDecoder().decode(Backup.self,from:Data(contentsOf:folder.appendingPathComponent("collection.json")))
        guard backup.schema==1 else { throw AppFailure.message("This backup format is not supported") }
        try await Task.detached(priority:.utility) {
            for track in backup.tracks {
                let source=try MediaPaths.file(track.file,under:folder.appendingPathComponent("Audio")).resolvingSymlinksInPath()
                guard source.path.hasPrefix(folder.resolvingSymlinksInPath().path+"/") else { throw LibraryError.unsafePath }
                let file=try FileHandle(forReadingFrom:source); defer { try? file.close() }; var hash=SHA256()
                while let chunk=try file.read(upToCount:1_048_576),!chunk.isEmpty { hash.update(data:chunk) }
                let digest=hash.finalize().map { String(format:"%02x",$0) }.joined()
                guard digest==track.digest else { throw AppFailure.message("A backup audio file failed its integrity check") }
                if !FileManager.default.fileExists(atPath:Disk.audio(track.file).path) { try FileManager.default.copyItem(at:source,to:Disk.audio(track.file)) }
                if let name=track.artwork {
                    let art=try MediaPaths.file(name,under:folder.appendingPathComponent("Artwork")).resolvingSymlinksInPath()
                    guard art.path.hasPrefix(folder.resolvingSymlinksInPath().path+"/") else { throw LibraryError.unsafePath }
                    if !FileManager.default.fileExists(atPath:Disk.art(name).path),FileManager.default.fileExists(atPath:art.path) { try FileManager.default.copyItem(at:art,to:Disk.art(name)) }
                }
            }
        }.value
        try await store.restore(tracks:backup.tracks,playlists:backup.playlists); try await refresh()
    }
    private func migrateLegacyIfNeeded(_ store:LibraryStore) async throws {
        let old=Disk.root.appendingPathComponent("catalog.json")
        guard FileManager.default.fileExists(atPath:old.path) else { return }
        struct Legacy:Decodable { var tracks:[Track]; var playlists:[LegacyList] }; struct LegacyList:Decodable { var id:UUID; var name:String; var tracks:[UUID] }
        let value=try JSONDecoder().decode(Legacy.self,from:Data(contentsOf:old))
        try await store.restore(tracks:value.tracks,playlists:value.playlists.map { Playlist(id:$0.id,name:$0.name,tracks:$0.tracks) })
        try FileManager.default.moveItem(at:old,to:old.appendingPathExtension("migrated"))
    }
}
