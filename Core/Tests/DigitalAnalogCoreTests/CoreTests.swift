import XCTest
@testable import DigitalAnalogCore

final class CoreTests: XCTestCase {
    func store() throws -> LibraryStore { let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); return try LibraryStore(url:dir.appendingPathComponent("collection.sqlite")) }
    func t(_ name:String, source:String? = nil) -> Track { Track(title:name,file:name+".m4a",duration:180,digest:name,sourceID:source) }
    func testPersistenceAcrossNewConnections() async throws {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("db.sqlite")
        let a=try LibraryStore(url:url); let track=t("first"); _=try await a.insert(track)
        let b=try LibraryStore(url:url); let saved=try await b.tracks(); XCTAssertEqual(saved,[track])
    }
    func testExactDuplicatesPreserveEditsAndIdentity() async throws {
        let db=try store(); let original=t("one"); _=try await db.insert(original)
        var edited=original; edited.title="Correct title"; edited.favorite=true; try await db.update(edited)
        let duplicate=try await db.insert(t("one")); XCTAssertEqual(duplicate.id,original.id); XCTAssertEqual(duplicate.title,"Correct title"); XCTAssertTrue(duplicate.favorite)
    }
    func testSourceDuplicateDifferentEncodingIsNotAdded() async throws {
        let db=try store(); let a=t("a",source:"local-a"); _=try await db.insert(a)
        let b=try await db.insert(t("b",source:"local-a")); XCTAssertEqual(b.id,a.id)
        let rows=try await db.tracks(); XCTAssertEqual(rows.count,1)
    }
    func testPlaylistForeignKeyAndCascade() async throws {
        let db=try store(); let track=t("one"); _=try await db.insert(track); let list=try await db.createPlaylist("Night")
        try await db.add(track.id,to:list.id); try await db.add(track.id,to:list.id)
        var lists=try await db.playlists(); XCTAssertEqual(lists[0].tracks,[track.id])
        try await db.deleteTrack(track.id); lists=try await db.playlists(); XCTAssertTrue(lists[0].tracks.isEmpty)
        let healthy=try await db.integrityCheck(); XCTAssertTrue(healthy)
    }
    func testMissingTrackCannotEnterPlaylist() async throws {
        let db=try store(); let list=try await db.createPlaylist("Night")
        do { try await db.add(UUID(),to:list.id); XCTFail("Expected FK failure") } catch { }
        let lists=try await db.playlists(); XCTAssertTrue(lists[0].tracks.isEmpty)
    }
    func testPlaylistOrderSurvivesAndInvalidOrderDoesNotMutate() async throws {
        let db=try store(); let a=t("a"),b=t("b"); _=try await db.insert(a); _=try await db.insert(b); let list=try await db.createPlaylist("Order")
        try await db.add(a.id,to:list.id); try await db.add(b.id,to:list.id); try await db.reorderPlaylist(list.id,tracks:[b.id,a.id])
        do { try await db.reorderPlaylist(list.id,tracks:[a.id,a.id]); XCTFail("Invalid permutation") } catch { }
        let lists=try await db.playlists(); XCTAssertEqual(lists[0].tracks,[b.id,a.id])
    }
    func testUpdateConstraintFailureLeavesOriginalIntact() async throws {
        let db=try store(); let a=t("a"),b=t("b"); _=try await db.insert(a); _=try await db.insert(b)
        var corrupt=b; corrupt.digest=a.digest
        do { try await db.update(corrupt); XCTFail("Unique constraint should fail") } catch { }
        let saved=try await db.track(id:b.id); XCTAssertEqual(saved,b)
    }
    func testDeletionReconcilesPersistentQueue() async throws {
        let db=try store(); let a=t("a"),b=t("b"); _=try await db.insert(a); _=try await db.insert(b)
        try await db.saveQueue(QueueState(ids:[a.id,b.id],current:a.id,position:50)); try await db.deleteTrack(a.id)
        let q=try await db.queue(); XCTAssertEqual(q.ids,[b.id]); XCTAssertEqual(q.current,b.id); XCTAssertEqual(q.position,0)
    }
    func testNoBlankPlaylistNames() async throws {
        let db=try store(); do { _=try await db.createPlaylist(" \n "); XCTFail("Blank") } catch { XCTAssertEqual(error as? LibraryError,.invalidName) }
    }
    func testPathTraversalRejected() {
        for name in ["../audio.m4a","/etc/passwd","..","x/y","x\\y",""] { XCTAssertThrowsError(try MediaPaths.file(name,under:URL(fileURLWithPath:"/library"))) }
    }
    func testQueueRemovalCurrentKeepsNavigationWorking() {
        let a=UUID(),b=UUID(),c=UUID(); var q=QueueState(ids:[a,b,c],current:b,position:42); q.remove(b)
        XCTAssertEqual(q.current,c); XCTAssertEqual(q.previous(),a); XCTAssertEqual(q.next(),c)
    }
    func testQueueEndRepeatAndEmptyBehavior() {
        let a=UUID(),b=UUID(); var q=QueueState(ids:[a,b],current:b)
        XCTAssertNil(q.next(automatic:true)); XCTAssertEqual(q.current,b)
        q.repeatMode = .all; XCTAssertEqual(q.next(automatic:true),a)
        q.repeatMode = .one; XCTAssertEqual(q.next(automatic:true),a)
        q.remove(a); q.remove(b); XCTAssertNil(q.next()); XCTAssertNil(q.previous())
    }
    func testShuffleDoesNotRepeatUntilCycleEndsAndPreviousUsesHistory() {
        let a=UUID(),b=UUID(),c=UUID(); var q=QueueState(ids:[a,b,c],current:a,shuffle:true)
        XCTAssertEqual(q.next(automatic:true,choose:{_ in 0}),b); XCTAssertEqual(q.next(automatic:true,choose:{_ in 0}),c); XCTAssertNil(q.next(automatic:true))
        XCTAssertEqual(q.previous(),b)
    }
    func testQueueRestorationAndReconciliation() throws {
        let a=UUID(),b=UUID(); var q=QueueState(ids:[a,b,a],current:a,position:30,shuffle:true,repeatMode:.all)
        q=try JSONDecoder().decode(QueueState.self,from:JSONEncoder().encode(q)); XCTAssertEqual(q.ids,[a,b]); q.reconcile(available:[b]); XCTAssertEqual(q.current,b)
    }
    func testInvalidQueueReorderIsRejected() {
        let a=UUID(),b=UUID(); var q=QueueState(ids:[a,b],current:a); XCTAssertThrowsError(try q.reorder([a,a])); XCTAssertEqual(q.ids,[a,b])
    }
    func testMetadataDoesNotConfuseLiveAndStudio() {
        let r=Recording(id:"id",title:"A Song (Live)",artist:"Artist",duration:200)
        let studio=MetadataCandidate(recordingID:"r",title:"A Song",artist:"Artist",duration:200)
        XCTAssertEqual(MetadataMatcher.score(r,studio),0); XCTAssertNil(MetadataMatcher.confident(r,candidates:[studio]))
    }
    func testAmbiguousAlbumIsNotAutomaticallyAssigned() {
        let r=Recording(id:"id",title:"A Song",artist:"Artist",duration:200)
        let a=MetadataCandidate(recordingID:"r",title:"A Song",artist:"Artist",duration:200,releaseID:"album1")
        var b=a; b.releaseID="album2"; XCTAssertNil(MetadataMatcher.confident(r,candidates:[a,b])); XCTAssertEqual(MetadataMatcher.confident(r,candidates:[a]),a)
    }
    func testWrongArtistAndDurationDoNotMatch() {
        let r=Recording(id:"id",title:"A Song",artist:"Artist",duration:200)
        let a=MetadataCandidate(recordingID:"r",title:"A Song",artist:"Other",duration:200)
        var b=a; b.artist="Artist"; b.duration=250
        XCTAssertNil(MetadataMatcher.confident(r,candidates:[a])); XCTAssertEqual(MetadataMatcher.score(r,b),0)
    }
    func testMetadataJSONParsingConvertsMillisecondsAndKeepsReleaseID() throws {
        let json=#"{"recordings":[{"id":"r","title":"Song","length":180000,"artist-credit":[{"name":"Artist"}],"releases":[{"id":"release","title":"Album","date":"1994-01-01","status":"Official"}]}]}"#
        let c=try MetadataResponse.candidates(from:Data(json.utf8))[0]; XCTAssertEqual(c.duration,180); XCTAssertEqual(c.year,1994); XCTAssertEqual(c.releaseID,"release")
    }
    func testRetryPolicyHonorsRateLimitAndDoesNotRetryForbidden() {
        XCTAssertTrue(RetryPolicy.retryable(status:429)); XCTAssertFalse(RetryPolicy.retryable(status:403)); XCTAssertEqual(RetryPolicy.delay(attempt:0,retryAfter:"17"),17); XCTAssertEqual(RetryPolicy.delay(attempt:4),16); XCTAssertEqual(RetryPolicy.delay(attempt:99),30)
    }
    func testSinglesDoNotBecomeAnInventedAlbum() { let a=t("a"),b=t("b"); XCTAssertNotEqual(a.albumKey,b.albumKey) }
    func testSnapshotExportsWithoutNetwork() async throws {
        let db=try store(); _=try await db.insert(t("a")); let data=try await db.exportSnapshot(); let object=try JSONSerialization.jsonObject(with:data) as? [String:Any]; XCTAssertEqual(object?["schema"] as? Int,1)
    }
    func testBackupRestorePreservesPlaylistIdentityAndIsIdempotent() async throws {
        let db=try store(); let a=t("a"); let list=Playlist(name:"Night",tracks:[a.id])
        try await db.restore(tracks:[a],playlists:[list]); try await db.restore(tracks:[a],playlists:[list])
        let lists=try await db.playlists(); XCTAssertEqual(lists,[list]); let records=try await db.tracks(); XCTAssertEqual(records,[a])
    }
    func testBadBackupRollsBackAllImportedRecords() async throws {
        let db=try store(); let a=t("a"); let invalid=Playlist(name:"Bad",tracks:[UUID()])
        do { try await db.restore(tracks:[a],playlists:[invalid]); XCTFail("Expected failure") } catch { }
        let records=try await db.tracks(); let lists=try await db.playlists(); XCTAssertTrue(records.isEmpty); XCTAssertTrue(lists.isEmpty)
    }

    func testArtworkUsesSameRecordingAcrossAmbiguousReleasesWithoutAssigningAlbum() {
        let source=Recording(id:"local",title:"Song",artist:"Artist",duration:200)
        let values=[MetadataCandidate(recordingID:"same",title:"Song",artist:"Artist",duration:200,releaseID:"a",album:"Original"),MetadataCandidate(recordingID:"same",title:"Song",artist:"Artist",duration:200,releaseID:"b",album:"Collection")]
        XCTAssertNil(MetadataMatcher.confident(source,candidates:values))
        XCTAssertEqual(MetadataMatcher.artworkCandidates(source,candidates:values).count,2)
    }
    func testArtworkStillRejectsAmbiguousRecordingsAndWrongVersions() {
        let source=Recording(id:"local",title:"Song",artist:"Artist",duration:200)
        let a=MetadataCandidate(recordingID:"a",title:"Song",artist:"Artist",duration:200,releaseID:"a")
        let b=MetadataCandidate(recordingID:"b",title:"Song",artist:"Artist",duration:200,releaseID:"b")
        XCTAssertTrue(MetadataMatcher.artworkCandidates(source,candidates:[a,b]).isEmpty)
        let live=MetadataCandidate(recordingID:"live",title:"Song (Live)",artist:"Artist",duration:200,releaseID:"live")
        XCTAssertTrue(MetadataMatcher.artworkCandidates(source,candidates:[live]).isEmpty)
    }
    func testDominantArtworkColorKeepsRedAgainstBlackAndWhite() {
        let pixels=Array(repeating:ArtworkRGB(0,0,0),count:90)+Array(repeating:ArtworkRGB(1,1,1),count:20)+Array(repeating:ArtworkRGB(0.8,0.05,0.02),count:12)
        let color=ArtworkPalette.dominant(pixels)
        XCTAssertGreaterThan(color.red,0.7);XCTAssertLessThan(color.green,0.1)
        XCTAssertEqual(ArtworkPalette.dominant([ArtworkRGB(0,0,0)]),ArtworkRGB(0.28,0.26,0.23))
    }
    func testAlbumFocusWrapsRetainsIdentityAndBoundsLargeLibraries() {
        let ids=(0..<10000).map(String.init); var focus=AlbumFocus(ids:ids)
        focus.advance(-1);XCTAssertEqual(focus.selected,"9999")
        XCTAssertEqual(focus.window().count,5)
        focus.reconcile(["x","9999","y"]);XCTAssertEqual(focus.selected,"9999")
        focus.reconcile(["x","y"]);XCTAssertEqual(focus.selected,"x")
        focus.reconcile([]);XCTAssertNil(focus.selected);XCTAssertTrue(focus.window().isEmpty)
    }
    func testAlbumFocusSmallLibrariesDoNotDuplicateOrLoseTheCenter() {
        var focus=AlbumFocus(ids:["a","a","b"])
        XCTAssertEqual(focus.window().first,"a");XCTAssertEqual(Set(focus.window()).count,2)
        focus.advance(1);XCTAssertEqual(focus.window().first,"b")
        focus.select("missing");XCTAssertEqual(focus.selected,"b")
    }
    func testLocalLyricsParseMultipleTimestampsOffsetAndPlainText() {
        let lrc=LyricsDocument("[offset:-500]\n[00:01.20][00:03.000]A line\n[00:05]Next line")
        XCTAssertTrue(lrc.synchronized);XCTAssertEqual(lrc.lines.count,3)
        XCTAssertEqual(lrc.lines.first?.time ?? 0,0.7,accuracy:0.001)
        XCTAssertNil(lrc.activeID(at:0.2));XCTAssertEqual(lrc.activeID(at:3),lrc.lines[1].id)
        let plain=LyricsDocument("First line\nSecond line")
        XCTAssertFalse(plain.synchronized);XCTAssertEqual(plain.lines.map(\.text),["First line","Second line"])
    }
    func testLegacyTrackWithoutLyricsStillDecodes() throws {
        let track=t("old");let bytes=try JSONEncoder().encode(track)
        var object=try XCTUnwrap(JSONSerialization.jsonObject(with:bytes) as? [String:Any]);object.removeValue(forKey:"lyrics")
        let decoded=try JSONDecoder().decode(Track.self,from:JSONSerialization.data(withJSONObject:object))
        XCTAssertEqual(decoded.id,track.id);XCTAssertNil(decoded.lyrics)
    }

    func testOfflineMoodsUseGenreTagsWithoutGuessingFromArtist() {
        var track=t("mood");track.artist="A famous artist"
        XCTAssertFalse(LibraryMood.chill.matches(track))
        track.genre="Jazz / Soul";XCTAssertTrue(LibraryMood.chill.matches(track));XCTAssertTrue(LibraryMood.focus.matches(track))
        track.genre="Hip-hop";XCTAssertTrue(LibraryMood.workout.matches(track))
    }
    func testLocalSearchCoversSongsAlbumsArtistsAndPlaylists() {
        var a=t("Nights");a.artist="Frank Ocean";a.album="Blonde"
        var b=t("Ivy");b.artist="Frank Ocean";b.album="Blonde"
        var c=t("Late Night Drive");c.artist="Somebody Else";c.genre="Jazz"
        var d=t("Café");d.artist="Élodie"
        let list=Playlist(name:"Night Studies",tracks:[a.id])
        let found=LibrarySearch.search("night",tracks:[c,a,b,d],playlists:[list,Playlist(name:"Morning")])
        XCTAssertEqual(found.tracks.map(\.id),[a.id,c.id],"Title-prefix matches rank first; library order is otherwise kept")
        XCTAssertTrue(found.albums.isEmpty);XCTAssertTrue(found.artists.isEmpty);XCTAssertEqual(found.playlists,[list])
        let artist=LibrarySearch.search("frank ocean",tracks:[c,a,b,d],playlists:[])
        XCTAssertEqual(artist.artists,["Frank Ocean"]);XCTAssertEqual(artist.albums,[a.albumKey]);XCTAssertEqual(artist.tracks.count,2)
        XCTAssertEqual(LibrarySearch.search("elodie cafe",tracks:[a,d],playlists:[]).tracks.map(\.id),[d.id],"Case and diacritics are ignored")
        XCTAssertEqual(LibrarySearch.search("jazz",tracks:[a,c],playlists:[]).tracks.map(\.id),[c.id],"Genre tags are searchable")
        XCTAssertTrue(LibrarySearch.search("  ",tracks:[a],playlists:[list]).isEmpty)
        XCTAssertTrue(LibrarySearch.search("blonde",tracks:[t("x")],playlists:[]).isEmpty)
    }
    func testSinglesAreNotListedAsAlbumsAndArtistLookupIgnoresCase() {
        var a=t("Solo");a.artist="Artist"
        var b=t("Other");b.artist="ARTIST";b.album="Record"
        let found=LibrarySearch.search("artist",tracks:[a,b],playlists:[])
        XCTAssertEqual(found.albums,[b.albumKey]);XCTAssertEqual(found.artists,["Artist"])
        XCTAssertEqual(LibrarySearch.tracks(byArtist:"artist",in:[a,b]).count,2)
    }

}
