import SwiftUI
import UniformTypeIdentifiers
import DigitalAnalogCore

struct TrackEditor:View {
    @EnvironmentObject private var library:Library
    @Environment(\.dismiss) private var dismiss
    @State var track:Track
    @State private var artworkPicker=false
    @State private var year=""
    @State private var candidates:[MetadataCandidate]=[]
    @State private var matching=false
    @State private var matchError:String?
    var body:some View {
        NavigationStack {
            Form {
                Cover(track:track).frame(width:165,height:165).frame(maxWidth:.infinity).listRowBackground(Color.clear)
                Section("Recording") {
                    TextField("Title",text:$track.title); TextField("Artist",text:$track.artist); TextField("Album",text:$track.album)
                    TextField("Year",text:$year).keyboardType(.numberPad)
                    TextField("Genre",text:Binding(get:{ track.genre ?? "" },set:{ track.genre=$0.isEmpty ? nil:$0 }))
                }
                Section("Artwork") {
                    Button("Choose cover from Files") { artworkPicker=true }
                    if let source=track.artworkSource { Text(source.hasPrefix("https:") ? "Saved from an online artwork source":source).font(.caption).foregroundStyle(DA.silver) }
                    Button { Task { await findMatches() } } label: { HStack { Text("Find album & artwork"); Spacer(); if matching { ProgressView() } } }.disabled(matching)
                    if let matchError { Text(matchError).font(.caption).foregroundStyle(DA.silver) }
                }
                if !candidates.isEmpty {
                    Section("Choose the correct release") {
                        ForEach(Array(candidates.enumerated()),id:\.offset) { _,candidate in
                            Button { Task { await choose(candidate) } } label: { VStack(alignment:.leading,spacing:5) { Text(candidate.album ?? candidate.title); Text("\(candidate.artist)\(candidate.year.map { " · \($0)" } ?? "")").font(.caption).foregroundStyle(DA.silver) } }.disabled(matching)
                        }
                    }
                }
            }.navigationTitle("Record details").toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement:.confirmationAction) { Button("Save") { track.year=Int(year); library.update(track); dismiss() }.disabled(track.title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || matching) }
            }.onAppear { year=track.year.map(String.init) ?? "" }
                .fileImporter(isPresented:$artworkPicker,allowedContentTypes:[.image]) { result in
                    Task {
                        do {
                            let url=try result.get(); let access=url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                            let bytes=try Data(contentsOf:url); guard bytes.count<20_000_000 else { throw AppFailure.message("Choose an image smaller than 20 MB") }
                            track.artwork=try await ArtworkFiles.store(bytes,key:UUID().uuidString); track.artworkSource="Selected from Files"
                        } catch { matchError=error.localizedDescription }
                    }
                }
        }.preferredColorScheme(.dark).foregroundStyle(DA.ivory).tint(DA.ivory)
    }
    private func findMatches() async {
        matching=true; matchError=nil; defer { matching=false }
        do {
            let source=Recording(id:track.sourceID ?? "",title:track.title,artist:track.artist,duration:track.duration)
            let found=try await ArtworkService.shared.candidates(source)
            candidates=found.sorted { MetadataMatcher.score(source,$0)>MetadataMatcher.score(source,$1) }
            if found.isEmpty { matchError="No matching releases were found. You can still edit this record manually." }
        } catch { matchError=error.localizedDescription }
    }
    private func choose(_ candidate:MetadataCandidate) async {
        matching=true; defer { matching=false }
        track.title=candidate.title; track.artist=candidate.artist; track.album=candidate.album ?? track.album; track.releaseID=candidate.releaseID; track.year=candidate.year; year=candidate.year.map(String.init) ?? ""
        do { if let cover=try await ArtworkService.shared.cover(for:candidate,key:UUID().uuidString) { track.artwork=cover; track.artworkSource="https://coverartarchive.org/release/\(candidate.releaseID ?? "")/front-500" } }
        catch { matchError="The release was selected, but its cover is unavailable. Your existing artwork is kept." }
    }
}
struct Mosaic:View {
    let tracks:[Track]
    var body:some View {
        ZStack {
            RoundedRectangle(cornerRadius:12).fill(.white.opacity(0.055))
            if tracks.isEmpty { ZStack { ForEach(0..<5) { i in Circle().stroke(DA.silver.opacity(0.12),lineWidth:1).padding(CGFloat(8+i*8)) }; Image(systemName:"square.stack").foregroundStyle(DA.silver) } }
            else {
                let chosen=Array(tracks.prefix(4))
                LazyVGrid(columns:[GridItem(.flexible(),spacing:2),GridItem(.flexible(),spacing:2)],spacing:2) { ForEach(0..<4) { i in Cover(track:chosen[i%chosen.count],radius:0) } }.clipShape(RoundedRectangle(cornerRadius:12))
            }
        }.aspectRatio(1,contentMode:.fit)
    }
}
struct PlaylistsView:View {
    @EnvironmentObject private var library:Library
    @Environment(\.dismiss) private var dismiss
    @State private var name=""
    var body:some View {
        NavigationStack {
            List {
                HStack { TextField("New personal collection",text:$name); Button { library.createPlaylist(name); name="" } label: { Image(systemName:"plus.circle").frame(width:44,height:44) }.disabled(name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty).accessibilityLabel("Create collection") }
                ForEach(library.catalog.playlists) { list in NavigationLink { PlaylistDetail(id:list.id) } label: {
                    HStack(spacing:16) { Mosaic(tracks:list.tracks.compactMap { id in library.catalog.tracks.first { $0.id==id } }).frame(width:65,height:65); VStack(alignment:.leading,spacing:6) { Text(list.name); Text("\(list.tracks.count) records").font(.caption).foregroundStyle(DA.silver) } }.padding(.vertical,6)
                }.listRowBackground(Color.clear).listRowSeparator(.hidden) }.onDelete { offsets in offsets.map { library.catalog.playlists[$0].id }.forEach { library.deletePlaylist($0) } }
                    .onMove { from,to in var order=library.catalog.playlists.map(\.id); order.move(fromOffsets:from,toOffset:to); library.reorderPlaylists(order) }
            }.listStyle(.plain).scrollContentBackground(.hidden).background(DA.black).navigationTitle("Playlists").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement:.topBarLeading) { Button("Done") { dismiss() } }; ToolbarItem(placement:.topBarTrailing) { EditButton() } }
        }.preferredColorScheme(.dark).foregroundStyle(DA.ivory).tint(DA.ivory)
    }
}
struct PlaylistDetail:View {
    let id:UUID
    @EnvironmentObject private var library:Library
    @EnvironmentObject private var playback:Playback
    @State private var adding=false
    @State private var renaming=false
    @State private var name=""
    private var duration:String { let minutes=Int(tracks.reduce(0) { $0+$1.duration }/60); return minutes>=60 ? "\(minutes/60)h \(minutes%60)m":"\(minutes)m" }
    private var list:Playlist? { library.catalog.playlists.first { $0.id==id } }
    private var tracks:[Track] { (list?.tracks ?? []).compactMap { id in library.catalog.tracks.first { $0.id==id } } }
    var body:some View {
        List {
            ZStack(alignment:.bottomLeading) {
                if let first=tracks.first { Cover(track:first,radius:0).frame(height:310).clipped().overlay(LinearGradient(stops:[.init(color:.black.opacity(0.02),location:0),.init(color:.black.opacity(0.12),location:0.35),.init(color:.black,location:0.72)],startPoint:.top,endPoint:.bottom)) }
                else { ListeningOrb().frame(height:310) }
                HStack(alignment:.bottom,spacing:15) {
                    VStack(alignment:.leading,spacing:10) {
                        Text(list?.name ?? "Playlist").font(.system(.largeTitle,design:.serif)).lineLimit(3)
                        Text("\(tracks.count) \(tracks.count == 1 ? "song":"songs") · \(duration)").font(.caption).foregroundStyle(DA.silver)
                    }; Spacer(minLength:0)
                    Button { if let first=tracks.first { playback.play(first,within:tracks) } } label: {
                        Image(systemName:"play.fill").font(.title3).frame(width:58,height:58).recordGlass(radius:29)
                    }.disabled(tracks.isEmpty).buttonStyle(.plain).accessibilityLabel("Play playlist")
                }.padding(20)
            }.frame(height:310).clipShape(RoundedRectangle(cornerRadius:12)).listRowInsets(EdgeInsets(top:6,leading:16,bottom:20,trailing:16)).listRowBackground(Color.clear).listRowSeparator(.hidden)
            ForEach(tracks) { track in Button { playback.play(track,within:tracks) } label: { HStack(spacing:13) { Cover(track:track,radius:5).frame(width:48,height:48); VStack(alignment:.leading,spacing:4) { Text(track.title); Text(track.artist).font(.caption).foregroundStyle(DA.silver) } } }.buttonStyle(.plain)
                .listRowBackground(Color.clear).listRowInsets(EdgeInsets(top:6,leading:16,bottom:6,trailing:16)) }
                .onDelete { offsets in offsets.map { tracks[$0].id }.forEach { library.removeFromPlaylist($0,playlist:id) } }
                .onMove { from,to in var order=list?.tracks ?? []; order.move(fromOffsets:from,toOffset:to); library.reorderPlaylist(id,tracks:order) }
        }.listStyle(.plain).scrollContentBackground(.hidden).background(DA.black).navigationTitle("Playlist").navigationBarTitleDisplayMode(.inline).toolbar {
            ToolbarItem(placement:.topBarTrailing) { Menu { Button("Add records") { adding=true }; Button("Rename") { name=list?.name ?? ""; renaming=true } } label: { Image(systemName:"ellipsis") }.accessibilityLabel("Collection actions") }
            ToolbarItem(placement:.topBarTrailing) { EditButton() }
        }.alert("Rename collection",isPresented:$renaming) { TextField("Name",text:$name); Button("Save") { library.renamePlaylist(id,name:name) }; Button("Cancel",role:.cancel) {} }
            .sheet(isPresented:$adding) { NavigationStack {
                List(library.catalog.tracks) { track in Button { library.addToPlaylist(track.id,playlist:id) } label: { HStack { Text(track.title); Spacer(); if list?.tracks.contains(track.id)==true { Image(systemName:"checkmark") } } } }.navigationTitle("Add records").toolbar { Button("Done") { adding=false } }
            }.preferredColorScheme(.dark) }
    }
}
