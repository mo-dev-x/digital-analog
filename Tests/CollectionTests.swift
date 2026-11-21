import XCTest
import UIKit
import AVFoundation
import SwiftUI
import MediaPlayer
import DigitalAnalogCore
@testable import DigitalAnalog

final class CollectionTests:XCTestCase {
    @MainActor func testNativeImportAndOfflineArtwork() async throws {
        let library=Library(); await library.start(); XCTAssertTrue(library.ready)
        let url=try XCTUnwrap(Bundle(for:Self.self).url(forResource:"tone",withExtension:"wav"))
        let first=try await library.ingest(url); let second=try await library.ingest(url)
        XCTAssertEqual(first.id,second.id)
        XCTAssertEqual(first.duration,1,accuracy:0.05)
        XCTAssertTrue(FileManager.default.fileExists(atPath:Disk.audio(first.file).path))
        let art=try XCTUnwrap(first.artwork); XCTAssertNotNil(UIImage(contentsOfFile:Disk.art(art).path))
        let restored=Library(); await restored.start(); XCTAssertTrue(restored.catalog.tracks.contains { $0.id==first.id })
    }
    @MainActor func testCorruptAudioIsRejected() async throws {
        let library=Library(); await library.start()
        let bad=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".m4a")
        try Data("not audio".utf8).write(to:bad); defer { try? FileManager.default.removeItem(at:bad) }
        do { _=try await library.ingest(bad); XCTFail("Corrupt input must not enter the collection") } catch { }
    }
    @MainActor func testLocalFallbackIsStableWithoutNetwork() async {
        let track=Track(title:"A record",file:"file.m4a",digest:"a")
        XCTAssertTrue(ArtworkCache.fallback(track) === ArtworkCache.fallback(track))
        XCTAssertEqual(ArtworkCache.fallback(track).size.width,600)
    }
    @MainActor func testPlaybackRestoresPausedQueueAndPosition() async throws {
        let library=Library(); await library.start()
        let fixture=try XCTUnwrap(Bundle(for:Self.self).url(forResource:"tone",withExtension:"wav"))
        let track=try await library.ingest(fixture)
        let store=try XCTUnwrap(library.store)
        try await store.saveQueue(QueueState(ids:[track.id],current:track.id,position:0.35))
        let playback=Playback(library:library); await playback.restore()
        XCTAssertEqual(playback.current?.id,track.id)
        XCTAssertEqual(playback.position,0.35,accuracy:0.05)
        XCTAssertFalse(playback.playing)
        playback.seek(0.6); await playback.flush()
        let saved=try await store.queue()
        XCTAssertEqual(saved.position,0.6,accuracy:0.05)
        playback.removeFromQueue(track.id)
        XCTAssertNil(playback.current); XCTAssertTrue(playback.queue.isEmpty)
    }

    @MainActor func testOfflinePlaybackAndCollectionPersistence() async throws {
        let library=Library(); await library.start()
        let fixture=try XCTUnwrap(Bundle(for:Self.self).url(forResource:"tone",withExtension:"wav"))
        var track=try await library.ingest(fixture)
        let store=try XCTUnwrap(library.store)
        track.favorite=true; try await store.update(track)
        let list=try await store.createPlaylist("Offline test \(UUID().uuidString)")
        try await store.add(track.id,to:list.id); try await library.refresh()
        let playback=Playback(library:library)
        playback.play(track,within:[track])
        defer { playback.pause() }
        for _ in 0..<100 {
            if playback.playing && playback.position>0 { break }
            try await Task.sleep(nanoseconds:20_000_000)
        }
        XCTAssertTrue(playback.playing,"AVPlayer must actually enter playing state for the local file")
        XCTAssertGreaterThan(playback.position,0)
        XCTAssertEqual(MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyTitle] as? String,track.title)
        playback.pause(); await playback.flush()
        XCTAssertFalse(playback.playing)
        let restored=Library(); await restored.start()
        XCTAssertEqual(restored.catalog.tracks.first(where:{$0.id==track.id})?.favorite,true)
        XCTAssertEqual(restored.catalog.playlists.first(where:{$0.id==list.id})?.tracks,[track.id])
        // Check real file export/restore as well as the portable SQL transactions.
        let backup=try await library.export()
        defer { try? FileManager.default.removeItem(at:backup) }
        try await restored.restoreBackup(backup)
        XCTAssertEqual(restored.catalog.tracks.filter({$0.digest==track.digest}).count,1)
    }
    @MainActor func testArtworkFilesKeepOriginalAspectAndRemainOffline() async throws {
        let image=UIGraphicsImageRenderer(size:CGSize(width:400,height:200)).image { context in
            UIColor.red.setFill();context.fill(CGRect(x:0,y:0,width:400,height:200))
        }
        let bytes=try XCTUnwrap(image.pngData());let name=try await ArtworkFiles.store(bytes,key:UUID().uuidString)
        let saved=try XCTUnwrap(UIImage(contentsOfFile:Disk.art(name).path))
        XCTAssertEqual(saved.size.width/saved.size.height,2,accuracy:0.01)
        let library=Library();await library.start()
        let url=try XCTUnwrap(Bundle(for:Self.self).url(forResource:"tone",withExtension:"wav"))
        var track=try await library.ingest(url);track.artwork=name;track.artworkSource="User-selected test cover"
        let store=try XCTUnwrap(library.store);try await store.update(track)
        let reopened=Library();await reopened.start()
        let persisted=try XCTUnwrap(reopened.catalog.tracks.first { $0.id==track.id })
        let loaded=await ArtworkCache.image(persisted)
        XCTAssertEqual(loaded.size.width/loaded.size.height,2,accuracy:0.01)
    }
    @MainActor func testNativeCanvasAndPlayerRendering() async throws {
        let services=Services(); await services.start()
        // Each render run owns its catalogue; other persistence tests must not
        // leak their diagnostic images or playlists into the visual comparison.
        let visualStore=try XCTUnwrap(services.library.store)
        for old in try await visualStore.tracks() { try await visualStore.deleteTrack(old.id) }
        for old in try await visualStore.playlists() { try await visualStore.deletePlaylist(old.id) }
        try await services.library.refresh()
        let fixture=try XCTUnwrap(Bundle(for:Self.self).url(forResource:"tone",withExtension:"wav"))
        var examples:[Track]=[]
        // User-supplied reference artwork is isolated to the test bundle.
        // Audio is synthetic, not these artists' recordings. No demo media ships.
        let referenceURL=try XCTUnwrap(Bundle(for:Self.self).url(forResource:"visual-reference",withExtension:"jpeg"))
        let reference=try XCTUnwrap(UIImage(contentsOfFile:referenceURL.path)?.cgImage)
        let records:[(String,String,String,CGRect)]=[
            ("Blinding Lights","The Weeknd","After Hours",CGRect(x:595,y:103,width:204,height:204)),
            ("FE!N","Travis Scott","UTOPIA",CGRect(x:1164,y:168,width:61,height:66)),
            ("Nights","Frank Ocean","Blonde",CGRect(x:1234,y:168,width:61,height:66)),
            ("EARFQUAKE","Tyler, The Creator","IGOR",CGRect(x:1092,y:289,width:61,height:66)),
            ("LOVE.","Kendrick Lamar","DAMN.",CGRect(x:1164,y:289,width:61,height:66)),
            ("Kill Bill","SZA","SOS",CGRect(x:1092,y:413,width:61,height:69)),
            ("No Role Modelz","J. Cole","2014 Forest Hills Drive",CGRect(x:1164,y:413,width:61,height:69)),
            ("Flashing Lights","Kanye West","Graduation",CGRect(x:1234,y:413,width:61,height:69))]
        for (index,record) in records.enumerated() {
            var data=try Data(contentsOf:fixture)
            // Repeat PCM frames, fixing both RIFF and data lengths. Duration is
            // measured by the importer from a real 200-second audio container.
            let header=data.prefix(44);let pcm=data.dropFirst(44)
            data=Data(header)
            for _ in 0..<200 { data.append(pcm) }
            var riff=UInt32(data.count-8).littleEndian;var length=UInt32(data.count-44).littleEndian
            withUnsafeBytes(of:&riff) { data.replaceSubrange(4..<8,with:$0) }
            withUnsafeBytes(of:&length) { data.replaceSubrange(40..<44,with:$0) }
            data[data.count-1]=UInt8(index+20)
            let input=FileManager.default.temporaryDirectory.appendingPathComponent("reference-\(index).wav");try data.write(to:input)
            let crop=try XCTUnwrap(reference.cropping(to:record.3))
            let bytes=try XCTUnwrap(UIImage(cgImage:crop).pngData())
            let cover=try await ArtworkFiles.store(bytes,key:"reference-\(index)")
            let recording=Recording(id:String(format:"visual%05d",index),title:record.0,artist:record.1,album:record.2)
            let art=ArtworkResolution(file:cover,match:nil,provenance:"User-supplied design reference; visual test only")
            let track=try await services.library.ingest(input,recording:recording,artwork:art)
            examples.append(track)
            try? FileManager.default.removeItem(at:input)
        }
        let track=try XCTUnwrap(examples.first)
        XCTAssertGreaterThan(track.duration,190)
        let store=try XCTUnwrap(services.library.store)
        let playlist=try await store.createPlaylist("Late Night Sessions")
        for example in examples { try await store.add(example.id,to:playlist.id) }
        try await store.saveQueue(QueueState(ids:examples.map(\.id),current:track.id))
        try await services.library.refresh(); await services.playback.restore()
        for (perspective,name) in [("Room","ListeningRoom"),("Collection","Collection"),("Browser","Albums")] {
            let canvas=Canvas(initialPerspective:perspective).environmentObject(services).environmentObject(services.library)
                .environmentObject(services.playback)
            try await capture(canvas,name:name)
        }
        for study in CollectionStudy.allCases {
            try await capture(CollectionStudyHost(albums:AlbumGroup.collect(examples),study:study),name:"Study-\(study.rawValue)")
        }
        try await capture(PlayerRenderHost(track:track).environmentObject(services.playback)
            .environmentObject(services.library),name:"NowPlaying")
        try await capture(SearchRenderHost().environmentObject(services).environmentObject(services.library).environmentObject(services.playback),name:"Search")
        try await capture(PlayerRenderHost(track:track).environmentObject(services.playback).environmentObject(services.library),name:"NowPlaying-SE",width:375,height:667)
        try await capture(PlayerRenderHost(track:track).environmentObject(services.playback).environmentObject(services.library).environment(\.dynamicTypeSize,.accessibility2),name:"NowPlaying-LargeType")
        try await capture(AlbumRenderHost(track:track).environmentObject(services.library),name:"AlbumDetail")
        try await capture(SearchRenderHost(query:"a").environmentObject(services).environmentObject(services.library).environmentObject(services.playback),name:"SearchResults")
        try await capture(SearchRenderHost(query:"Frank",scope:.artists).environmentObject(services).environmentObject(services.library).environmentObject(services.playback),name:"SearchArtists")
        try await capture(LyricsView(track:track).environmentObject(services.playback).environmentObject(services.library),name:"Lyrics")
        try await capture(SettingsView().environmentObject(services.library),name:"Settings")
        try await capture(QueueView().environmentObject(services.library).environmentObject(services.playback),name:"Queue")
        try await capture(NavigationStack { PlaylistDetail(id:playlist.id) }.environmentObject(services.library).environmentObject(services.playback),name:"Playlist")
    }
    @MainActor func testIndependentArtworkProviderAndOfflineImport() async throws {
        let library=Library();await library.start()
        let fixture=try XCTUnwrap(Bundle(for:Self.self).url(forResource:"tone",withExtension:"wav"))
        let cases:[(String,String,String)]=[("So What","Miles Davis","Kind of Blue"),("Diamonds","Rihanna","Unapologetic"),("HUMBLE.","Kendrick Lamar","DAMN."),("Unforgettable","Nat King Cole","Unforgettable")]
        for (index,item) in cases.enumerated() {
            let original=try Data(contentsOf:fixture)
            var bytes=Data(original.prefix(44));for _ in 0..<200 { bytes.append(original.dropFirst(44)) }
            var riff=UInt32(bytes.count-8).littleEndian;var count=UInt32(bytes.count-44).littleEndian
            withUnsafeBytes(of:&riff) { bytes.replaceSubrange(4..<8,with:$0) }
            withUnsafeBytes(of:&count) { bytes.replaceSubrange(40..<44,with:$0) }
            bytes[bytes.count-1]=UInt8(190+index)
            let input=FileManager.default.temporaryDirectory.appendingPathComponent("independent-art-\(index).wav")
            try bytes.write(to:input);defer { try? FileManager.default.removeItem(at:input) }
            let source=Recording(id:"artcase000\(index)",title:item.0,artist:item.1,album:item.2)
            let track=try await library.ingest(input,recording:source)
            XCTAssertTrue(track.artworkSource?.hasPrefix("https://coverartarchive.org/")==true,"\(item.1) / \(item.0): \(track.artworkSource ?? "nil")")
            let file=try XCTUnwrap(track.artwork);let image=try XCTUnwrap(UIImage(contentsOfFile:Disk.art(file).path))
            let attachment=XCTAttachment(image:image);attachment.name="Retrieved-\(item.1)";attachment.lifetime = .keepAlways;add(attachment)
            let reopened=Library();await reopened.start()
            XCTAssertEqual(reopened.catalog.tracks.first(where:{$0.id==track.id})?.artwork,file)
        }
        let live=Recording(id:"livecase000",title:"HUMBLE. (live)",artist:"Kendrick Lamar")
        let candidates=try await ArtworkService.shared.candidates(live)
        XCTAssertTrue(MetadataMatcher.artworkCandidates(live,candidates:candidates).allSatisfy { MetadataMatcher.qualifiers($0.title).contains("live") },"A live recording must never silently receive a studio match")
    }
    @MainActor func testScriptedNativeMotionStudy() async throws {
        let services=Services();await services.start()
        let track=try XCTUnwrap(services.library.catalog.tracks.first(where:{$0.artist=="The Weeknd"}))
        let scene=try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window=UIWindow(windowScene:scene)
        window.rootViewController=UIHostingController(rootView:MotionStudyHost(track:track).environmentObject(services.library).environmentObject(services.playback))
        window.frame=CGRect(x:0,y:0,width:392,height:852)
        window.makeKeyAndVisible();defer { window.isHidden=true }
        let url=FileManager.default.temporaryDirectory.appendingPathComponent("Native-motion.mp4")
        try? FileManager.default.removeItem(at:url)
        let writer=try AVAssetWriter(outputURL:url,fileType:.mp4)
        let input=AVAssetWriterInput(mediaType:.video,outputSettings:[AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:392,AVVideoHeightKey:852])
        let adaptor=AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32ARGB,kCVPixelBufferWidthKey as String:392,kCVPixelBufferHeightKey as String:852,kCVPixelBufferCGImageCompatibilityKey as String:true,kCVPixelBufferCGBitmapContextCompatibilityKey as String:true])
        writer.add(input);XCTAssertTrue(writer.startWriting());writer.startSession(atSourceTime:.zero)
        let start=Date()
        let format=UIGraphicsImageRendererFormat();format.scale=1
        let renderer=UIGraphicsImageRenderer(bounds:window.bounds,format:format)
        while Date().timeIntervalSince(start)<12 {
            if input.isReadyForMoreMediaData,let pool=adaptor.pixelBufferPool {
                var buffer:CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil,pool,&buffer)
                if let buffer {
                    let image=renderer.image { _ in window.drawHierarchy(in:window.bounds,afterScreenUpdates:false) }
                    CVPixelBufferLockBaseAddress(buffer,[])
                    if let context=CGContext(data:CVPixelBufferGetBaseAddress(buffer),width:392,height:852,bitsPerComponent:8,bytesPerRow:CVPixelBufferGetBytesPerRow(buffer),space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipFirst.rawValue),let cg=image.cgImage {
                        context.draw(cg,in:CGRect(x:0,y:0,width:392,height:852))
                    }
                    CVPixelBufferUnlockBaseAddress(buffer,[])
                    XCTAssertTrue(adaptor.append(buffer,withPresentationTime:CMTime(seconds:Date().timeIntervalSince(start),preferredTimescale:600)))
                }
            }
            try await Task.sleep(nanoseconds:33_333_333)
        }
        input.markAsFinished();await writer.finishWriting()
        XCTAssertEqual(writer.status,.completed)
        let video=XCTAttachment(contentsOfFile:url);video.name="Native-motion.mp4";video.lifetime = .keepAlways;add(video)
    }
    @MainActor private func capture<V:View>(_ view:V,name:String,width:CGFloat=393,height:CGFloat=852) async throws {
        let scene=try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window=UIWindow(windowScene:scene); window.frame=CGRect(x:0,y:0,width:width,height:height)
        let controller=UIHostingController(rootView:view.preferredColorScheme(.dark))
        window.rootViewController=controller; window.makeKeyAndVisible()
        defer { window.isHidden=true }
        controller.view.frame=window.bounds; controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds:500_000_000)
        let image=UIGraphicsImageRenderer(bounds:window.bounds).image { _ in
            XCTAssertTrue(window.drawHierarchy(in:window.bounds,afterScreenUpdates:true))
        }
        let attachment=XCTAttachment(image:image); attachment.name=name; attachment.lifetime = .keepAlways
        add(attachment)
    }

}

private struct PlayerRenderHost:View {
    let track:Track
    @Namespace private var space
    var body:some View { PlayerView(track:track,namespace:space,artworkID:"test",dismiss:{}) }
}

private struct SearchRenderHost:View {
    var query:String="";var scope:SearchScope = .all
    @Namespace private var space
    var body:some View { SearchOverlay(namespace:space,close:{},play:{ _,_,_ in },initialQuery:query,initialScope:scope) }
}

private struct AlbumRenderHost:View {
    let track:Track
    @Namespace private var space
    var body:some View { AlbumExperience(selection:AlbumSelection(id:track.albumKey,title:track.album,artist:track.artist,tracks:[track]),space:space,playerExpanded:false,play:{_ in},close:{},edit:{_ in}) }
}

private struct CollectionStudyHost:View {
    let albums:[AlbumGroup];let study:CollectionStudy
    @Namespace private var space
    var body:some View {
        VStack { Text(study.rawValue.capitalized).font(.largeTitle).padding(); AlbumCarousel(study:study,albums:albums,namespace:space,hiddenID:nil,open:{_ in});Spacer() }.background(DA.black).foregroundStyle(DA.ivory)
    }
}

private struct MotionStudyHost:View {
    let track:Track
    @State private var expanded=false
    @Namespace private var space
    var body:some View {
        ZStack {
            DA.black.ignoresSafeArea()
            if expanded {
                PlayerView(track:track,namespace:space,artworkID:"motion-cover",dismiss:{withAnimation(DA.spring){expanded=false}}).transition(.identity)
            } else {
                VStack(spacing:24) {
                    Text("Native motion study").font(.title2)
                    Text("Scripted expansion and reversal").font(.caption).foregroundStyle(DA.silver)
                    Cover(track:track).matchedGeometryEffect(id:"motion-cover",in:space).frame(width:116,height:116)
                }.foregroundStyle(DA.ivory).transition(.identity)
            }
        }.preferredColorScheme(.dark).task {
            for _ in 0..<3 {
                try? await Task.sleep(nanoseconds:1_500_000_000)
                withAnimation(DA.spring) { expanded=true }
                try? await Task.sleep(nanoseconds:1_500_000_000)
                withAnimation(DA.spring) { expanded=false }
            }
        }
    }
}
