#if DEBUG
import SwiftUI
import DigitalAnalogCore
/// Explicit UI-test launch only. Fixtures are copied into Debug builds only.
@MainActor enum InteractionFixtures {
    static func seed(_ services:Services) async throws {
        guard ProcessInfo.processInfo.arguments.contains("--ui-fixtures") else { return }
        guard let store=services.library.store else { return }
        if services.library.catalog.tracks.contains(where:{$0.sourceID=="gesture0000"}) { return }
        let imageURL=Bundle.main.url(forResource:"visual-reference",withExtension:"jpeg")!
        let image=UIImage(contentsOfFile:imageURL.path)!.cgImage!
        let audio=try Data(contentsOf:Bundle.main.url(forResource:"tone",withExtension:"wav")!)
        let records:[(String,String,String,CGRect)]=[
            ("Blinding Lights","The Weeknd","After Hours",CGRect(x:595,y:103,width:204,height:204)),
            ("Nights","Frank Ocean","Blonde",CGRect(x:1234,y:168,width:61,height:66)),
            ("LOVE.","Kendrick Lamar","DAMN.",CGRect(x:1164,y:289,width:61,height:66))]
        var tracks:[Track]=[]
        for (index,r) in records.enumerated() {
            var data=Data(audio.prefix(44));for _ in 0..<200 { data.append(audio.dropFirst(44)) }
            var riff=UInt32(data.count-8).littleEndian;var size=UInt32(data.count-44).littleEndian
            withUnsafeBytes(of:&riff) { data.replaceSubrange(4..<8,with:$0) }
            withUnsafeBytes(of:&size) { data.replaceSubrange(40..<44,with:$0) }
            data[data.count-1]=UInt8(90+index)
            let url=FileManager.default.temporaryDirectory.appendingPathComponent("gesture-\(index).wav")
            try data.write(to:url);defer { try? FileManager.default.removeItem(at:url) }
            let bytes=UIImage(cgImage:image.cropping(to:r.3)!).pngData()!
            let name=try await ArtworkFiles.store(bytes,key:"gesture-art-\(index)")
            let recording=Recording(id:"gesture000\(index)",title:r.0,artist:r.1,album:r.2)
            let track=try await services.library.ingest(url,recording:recording,artwork:ArtworkResolution(file:name,match:nil,provenance:"UI-test fixture; synthetic audio"))
            tracks.append(track)
        }
        let playlist=try await store.createPlaylist("Night Studies")
        for track in tracks { try await store.add(track.id,to:playlist.id) }
        try await services.library.refresh()
        let preferred=services.library.catalog.tracks.first { $0.artist=="Miles Davis" && $0.artworkSource?.hasPrefix("https://coverartarchive.org/")==true } ?? tracks[0]
        services.playback.play(preferred,within:services.library.catalog.tracks);services.playback.pause()
    }
}
#endif
