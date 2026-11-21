import SwiftUI
import DigitalAnalogCore

enum SearchScope:String,CaseIterable,Identifiable {
    case all="All",songs="Songs",albums="Albums",artists="Artists",playlists="Playlists"
    var id:String { rawValue }
}
private struct PlaylistRoute:Identifiable { let id:UUID }

/// Searches only the user's own library: songs, albums, artists and playlists. Works offline.
struct SearchOverlay:View {
    let namespace:Namespace.ID
    let close:()->Void
    let play:(Track,[Track],String)->Void
    let openAlbum:(AlbumGroup)->Void
    @EnvironmentObject private var library:Library
    @State private var query=""
    @State private var mood:LibraryMood?
    @State private var scope:SearchScope = .all
    @State private var artist:String?
    @State private var editing:Track?
    @State private var playlist:PlaylistRoute?
    @FocusState private var focused:Bool
    private let preview=6
    init(namespace:Namespace.ID,close:@escaping ()->Void,play:@escaping (Track,[Track],String)->Void,openAlbum:@escaping (AlbumGroup)->Void={ _ in },initialQuery:String="",initialScope:SearchScope = .all) {
        self.namespace=namespace;self.close=close;self.play=play;self.openAlbum=openAlbum
        _query=State(initialValue:initialQuery);_scope=State(initialValue:initialScope)
    }
    private var trimmed:String { query.trimmingCharacters(in:.whitespacesAndNewlines) }
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack(spacing:12) {
                Image(systemName:"magnifyingglass").foregroundStyle(DA.silver)
                TextField("Search your songs, albums, artists…",text:$query).font(.subheadline).focused($focused).submitLabel(.search).autocorrectionDisabled().textInputAutocapitalization(.never)
                Button(action:close) { Image(systemName:"xmark.circle.fill").frame(width:44,height:44).foregroundStyle(DA.silver) }.accessibilityLabel("Close search")
            }.padding(.leading,16).padding(.trailing,5).background(.white.opacity(0.075),in:Capsule()).overlay(Capsule().stroke(.white.opacity(0.1),lineWidth:0.5))
            ScrollView(.horizontal,showsIndicators:false) {
                HStack(spacing:10) {
                    ForEach(SearchScope.allCases) { item in
                        Button { scope=item } label: { Text(item.rawValue).font(.caption).padding(.horizontal,15).padding(.vertical,9).background(scope==item ? .white.opacity(0.23):.white.opacity(0.035),in:RoundedRectangle(cornerRadius:9)) }
                            .buttonStyle(.plain).accessibilityAddTraits(scope==item ? .isSelected:[])
                    }
                }
            }
            ScrollView {
                LazyVStack(alignment:.leading,spacing:12) {
                    if let artist { artistDetail(artist) }
                    else if let mood { moodResults(mood) }
                    else if trimmed.isEmpty {
                        MoodDiscovery { selected in mood=selected; query=selected.rawValue; focused=false }.padding(.top,28)
                    } else {
                        matches(LibrarySearch.search(trimmed,tracks:library.catalog.tracks,playlists:library.catalog.playlists))
                    }
                }.padding(.top,8).padding(.bottom,35)
            }.scrollDismissesKeyboard(.interactively)
        }.padding(.horizontal,22).padding(.top,14).background(DA.black.ignoresSafeArea()).foregroundStyle(DA.ivory).tint(DA.ivory)
            .onChange(of:query) { _,value in
                if let mood,value != mood.rawValue { self.mood=nil }
                artist=nil
            }
            .sheet(item:$editing) { TrackEditor(track:$0) }
            .sheet(item:$playlist) { route in
                NavigationStack {
                    PlaylistDetail(id:route.id).toolbar { ToolbarItem(placement:.topBarLeading) { Button("Done") { playlist=nil } } }
                }.preferredColorScheme(.dark).foregroundStyle(DA.ivory).tint(DA.ivory)
            }
    }
    @ViewBuilder private func matches(_ found:LibrarySearchResults)->some View {
        let all=scope == .all
        let groups=albumLookup
        let albums=found.albums.compactMap { groups[$0] }
        if (all || scope == .artists) && !found.artists.isEmpty {
            heading("Artists",more:all && found.artists.count>preview ? .artists:nil)
            ForEach(all ? Array(found.artists.prefix(preview)):found.artists,id:\.self) { artistRow($0) }
        }
        if (all || scope == .albums) && !albums.isEmpty {
            heading("Albums",more:all && albums.count>preview ? .albums:nil)
            ForEach(all ? Array(albums.prefix(preview)):albums) { albumRow($0) }
        }
        if (all || scope == .songs) && !found.tracks.isEmpty {
            heading("Songs",more:all && found.tracks.count>preview*2 ? .songs:nil)
            ForEach(all ? Array(found.tracks.prefix(preview*2)):found.tracks) { trackRow($0,context:found.tracks) }
        }
        if (all || scope == .playlists) && !found.playlists.isEmpty {
            heading("Playlists",more:all && found.playlists.count>preview ? .playlists:nil)
            ForEach(all ? Array(found.playlists.prefix(preview)):found.playlists) { playlistRow($0) }
        }
        if nothing(found,albums:albums) {
            Text(library.catalog.tracks.isEmpty ? "Your collection is empty. Import audio from Files to start.":"No matching records in your collection.").foregroundStyle(DA.silver).padding(.vertical,30)
        }
    }
    private func nothing(_ found:LibrarySearchResults,albums:[AlbumGroup])->Bool {
        switch scope {
        case .all: return found.tracks.isEmpty && albums.isEmpty && found.artists.isEmpty && found.playlists.isEmpty
        case .songs: return found.tracks.isEmpty
        case .albums: return albums.isEmpty
        case .artists: return found.artists.isEmpty
        case .playlists: return found.playlists.isEmpty
        }
    }
    @ViewBuilder private func artistDetail(_ name:String)->some View {
        let songs=LibrarySearch.tracks(byArtist:name,in:library.catalog.tracks)
        let groups=albumLookup
        let albums=AlbumGroup.collect(songs).filter { $0.cover.album != "Singles" }.map { groups[$0.id] ?? $0 }
        Button { artist=nil } label: { Label("All results",systemImage:"chevron.left").font(.caption).frame(minHeight:44) }.buttonStyle(.plain).foregroundStyle(DA.silver)
        HStack(alignment:.bottom) {
            VStack(alignment:.leading,spacing:6) {
                Text(name).font(.system(.title2,design:.serif))
                Text(plural(songs.count,"song")).font(.caption).foregroundStyle(DA.silver)
            }
            Spacer()
            if let first=songs.first {
                Button { play(first,songs,"search-\(first.id)") } label: { Image(systemName:"play.fill").font(.title3).frame(width:52,height:52).recordGlass(radius:26) }.buttonStyle(.plain).accessibilityLabel("Play \(name)")
            }
        }
        if !albums.isEmpty {
            heading("Albums")
            ForEach(albums) { albumRow($0) }
        }
        if !songs.isEmpty {
            heading("Songs")
            ForEach(songs) { trackRow($0,context:songs) }
        }
    }
    @ViewBuilder private func moodResults(_ mood:LibraryMood)->some View {
        let songs=library.catalog.tracks.filter { mood.matches($0) }
        Text("\(mood.rawValue) · using your genre tags").font(.caption).foregroundStyle(DA.silver)
        ForEach(songs) { trackRow($0,context:songs) }
        if songs.isEmpty { Text("No matching genre tags yet. Add a genre in Record details to explore this mood offline.").foregroundStyle(DA.silver) }
    }
    private var albumLookup:[String:AlbumGroup] {
        Dictionary(uniqueKeysWithValues:AlbumGroup.collect(library.catalog.tracks).map { ($0.id,$0) })
    }
    private func heading(_ title:String,more:SearchScope?=nil)->some View {
        HStack {
            Text(title.uppercased()).font(.caption2).tracking(2).foregroundStyle(DA.silver)
            Spacer()
            if let more { Button("See all") { scope=more }.font(.caption).foregroundStyle(DA.silver) }
        }.padding(.top,10)
    }
    private func trackRow(_ track:Track,context:[Track])->some View {
        RecordRow(track:track,action:{ focused=false; play(track,context,"search-\(track.id)") },edit:{ editing=track },namespace:namespace,artworkID:"search-\(track.id)")
    }
    private func albumRow(_ group:AlbumGroup)->some View {
        Button { focused=false; openAlbum(group) } label: {
            resultRow(title:group.title,detail:"\(group.cover.artist) · \(plural(group.tracks.count,"song"))") { Cover(track:group.cover,radius:5) }
        }.buttonStyle(.plain).accessibilityLabel("Album \(group.title), \(group.cover.artist)")
    }
    private func artistRow(_ name:String)->some View {
        Button { focused=false; artist=name } label: {
            resultRow(title:name,detail:plural(LibrarySearch.tracks(byArtist:name,in:library.catalog.tracks).count,"song")) {
                ZStack { Circle().fill(.white.opacity(0.06)); Image(systemName:"person.fill").font(.system(size:16)).foregroundStyle(DA.silver) }
            }
        }.buttonStyle(.plain).accessibilityLabel("Artist \(name)")
    }
    private func playlistRow(_ list:Playlist)->some View {
        Button { focused=false; playlist=PlaylistRoute(id:list.id) } label: {
            resultRow(title:list.name,detail:plural(list.tracks.count,"record")) {
                Mosaic(tracks:list.tracks.compactMap { id in library.catalog.tracks.first { $0.id==id } })
            }
        }.buttonStyle(.plain).accessibilityLabel("Playlist \(list.name)")
    }
    private func resultRow<Artwork:View>(title:String,detail:String,@ViewBuilder artwork:()->Artwork)->some View {
        HStack(spacing:12) {
            artwork().frame(width:46,height:46)
            VStack(alignment:.leading,spacing:4) {
                Text(title).font(.subheadline).foregroundStyle(DA.ivory).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(DA.silver.opacity(0.8)).lineLimit(1)
            }
            Spacer(minLength:0)
            Image(systemName:"chevron.right").font(.system(size:11,weight:.light)).foregroundStyle(DA.silver)
        }.padding(.vertical,3).contentShape(Rectangle())
    }
    private func plural(_ count:Int,_ noun:String)->String { "\(count) \(noun)\(count==1 ? "":"s")" }
}

private struct MoodDiscovery:View {
    let select:(LibraryMood)->Void
    private let moods:[(LibraryMood,CGFloat,CGFloat)]=[(.chill,0.25,0.28),(.sad,0.74,0.2),(.workout,0.8,0.58),(.love,0.68,0.86),(.focus,0.32,0.87),(.party,0.16,0.59)]
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            Text("A different\nkind of search.").font(.system(.title,design:.serif)).tracking(-0.7)
            Text("Start with the mood you’re in.").font(.subheadline).foregroundStyle(DA.silver.opacity(0.8))
            GeometryReader { geometry in
                ZStack {
                    ForEach(Array(moods.enumerated()),id:\.offset) { _,mood in
                        Button { select(mood.0) } label: {
                            ZStack {
                                Circle().fill(RadialGradient(colors:[.white.opacity(0.12),DA.surface,.black],center:.topLeading,startRadius:0,endRadius:95))
                                Circle().stroke(LinearGradient(colors:[.white.opacity(0.4),.clear,.white.opacity(0.07)],startPoint:.topLeading,endPoint:.bottomTrailing),lineWidth:0.7)
                                Text(mood.0.rawValue).font(.caption).foregroundStyle(DA.ivory)
                            }.frame(width:88,height:88).shadow(color:.black.opacity(0.7),radius:12,y:10)
                        }.buttonStyle(.plain).position(x:geometry.size.width*mood.1,y:geometry.size.height*mood.2)
                    }

                }
            }.frame(height:330).padding(.top,14)
            Text("Or type anything above.").font(.caption).foregroundStyle(DA.silver.opacity(0.6)).frame(maxWidth:.infinity).padding(.top,20)
        }
    }
}
