import SwiftUI
import DigitalAnalogCore

struct AlbumSelection:Identifiable { var id:String; var title:String; var artist:String; var tracks:[Track] }
struct Canvas:View {
    @EnvironmentObject private var library:Library
    @EnvironmentObject private var services:Services
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var space
    @State private var perspective="Room"
    @State private var lens="Albums"
    @State private var searching=false
    @State private var importing=false
    @State private var playlists=false
    @State private var settings=false
    @State private var editing:Track?
    @State private var album:AlbumSelection?
    @State private var expanded=false
    @State private var current:Track?
    @State private var source="compact"
    init(initialPerspective:String="Room",initialLens:String="Albums") {
        _perspective=State(initialValue:initialPerspective); _lens=State(initialValue:initialLens)
    }
    private let lenses=["Albums","Songs","Artists","Favorites","Recent","Decades","Genres"]
    private var motion:Animation? { reduceMotion ? nil:DA.spring }
    private var recent:[Track] { library.catalog.tracks.sorted { ($0.lastPlayed ?? $0.added)>($1.lastPlayed ?? $1.added) } }
    private var tracks:[Track] {
        switch lens {
        case "Favorites":return library.catalog.tracks.filter(\.favorite)
        case "Recent":return recent
        default:return library.catalog.tracks
        }
    }
    var body:some View {
        ZStack {
            DA.black.ignoresSafeArea()
            ScrollView {
                VStack(alignment:.leading,spacing:22) {
                    if perspective=="Room" { room }
                    else if perspective=="Collection" { collectionOverview }
                    else { browser }
                    if library.loading { ProgressView("Opening your collection…").tint(DA.silver).frame(maxWidth:.infinity).padding(.vertical,40) }
                    if library.importing { ProgressView("Adding records…").tint(DA.ivory) }
                }.padding(.horizontal,22).padding(.top,8).padding(.bottom,20)
            }.id(perspective).accessibilityHidden(album != nil || expanded || searching)
            if let album {
                AlbumExperience(selection:album,space:space,playerExpanded:expanded,play:{ track in play(track,within:album.tracks,source:"album-detail") },close:{ withAnimation(motion) { self.album=nil } },edit:{ editing=$0 },shuffle:{ if let first=album.tracks.randomElement() { services.playback.setShuffle(true); play(first,within:album.tracks,source:"album-detail") } })
                    .transition(.opacity).zIndex(1).accessibilityHidden(expanded)
            }
            if expanded,let current {
                PlayerView(track:current,namespace:space,artworkID:source,dismiss:{ withAnimation(motion) { expanded=false } }).zIndex(3).transition(.identity)
            }
            if searching {
                SearchOverlay(namespace:space,close:{ withAnimation(motion) { searching=false } },play:{ track,context,origin in source=origin; services.playback.play(track,within:context); withAnimation(motion) { searching=false; expanded=true } },openAlbum:{ group in withAnimation(motion) { searching=false }; openAlbum(group) })
                    .zIndex(4).transition(.opacity.combined(with:.scale(scale:reduceMotion ? 1:0.985)))
            }
        }.safeAreaInset(edge:.bottom,spacing:0) {
            if current != nil,!expanded,!searching {
                CompactPlayer(namespace:space,open:{ source="compact"; withAnimation(motion) { expanded=true } })
                    .padding(.horizontal,16).padding(.vertical,5)
            }
        }.foregroundStyle(DA.ivory).preferredColorScheme(.dark).tint(DA.ivory)
            .onChange(of:library.catalog.tracks) { _,tracks in
                if let selected=album {
                    let values=tracks.filter { $0.albumKey==selected.id }
                    if values.isEmpty { album=nil } else { album=AlbumSelection(id:selected.id,title:selected.title,artist:selected.artist,tracks:values) }
                }
            }
            .onReceive(services.playback.$current) { current=$0; if $0==nil { expanded=false } }
            .onChange(of:scenePhase) { _,phase in if phase != .active { Task { await services.playback.flush() } } }
            .fileImporter(isPresented:$importing,allowedContentTypes:[.audio,.mpeg4Movie],allowsMultipleSelection:true) { result in
                switch result { case .success(let urls):Task { await library.add(urls) }; case .failure(let error):library.error=error.localizedDescription }
            }
            .sheet(isPresented:$playlists) { PlaylistsView() }
            .sheet(isPresented:$settings) { SettingsView() }
            .sheet(item:$editing) { TrackEditor(track:$0) }
            .alert("Digital Analog",isPresented:Binding(get:{ library.error != nil },set:{ if !$0 { library.error=nil } })) { Button("OK") { library.error=nil } } message: { Text(library.error ?? "") }
    }
    private var room:some View {
        VStack(alignment:.leading,spacing:20) {
            ZStack(alignment:.topLeading) {
                if let hero=current ?? recent.first {
                    Cover(track:hero,radius:0).frame(width:265,height:300).clipped()
                        .mask(LinearGradient(stops:[.init(color:.clear,location:0),.init(color:.black.opacity(0.75),location:0.55),.init(color:.black,location:1)],startPoint:.leading,endPoint:.trailing))
                        .mask(LinearGradient(colors:[.black,.black,.clear],startPoint:.top,endPoint:.bottom))
                        .frame(maxWidth:.infinity,alignment:.trailing).accessibilityHidden(true)
                } else {
                    ListeningOrb().frame(width:240,height:240).opacity(0.7).frame(maxWidth:.infinity,alignment:.trailing).accessibilityHidden(true)
                }
                VStack(alignment:.leading,spacing:18) {
                    HStack(alignment:.top) {
                        VStack(alignment:.leading,spacing:9) {
                            Text("YOUR LISTENING ROOM").font(.system(size:9,weight:.medium)).tracking(1.8).foregroundStyle(DA.silver.opacity(0.7))
                            Text("Music hits\ndifferent here.").font(.system(.title,design:.serif)).tracking(-0.7).lineSpacing(1)
                        }
                        Spacer(); options
                    }
                    Spacer(minLength:4)
                    Button { showSearch() } label: {
                        HStack(spacing:11) { Image(systemName:"magnifyingglass").font(.subheadline); Text("Search your songs, albums, artists…").font(.caption).foregroundStyle(DA.silver); Spacer(minLength:0); Image(systemName:"waveform").font(.subheadline) }
                            .padding(.horizontal,16).frame(height:50)
                            .recordGlass(radius:25).overlay(Capsule().stroke(.white.opacity(0.28),lineWidth:0.6))
                    }.buttonStyle(.plain).accessibilityLabel("Search your collection")
                }.padding(.top,14).padding(.bottom,18)
            }.frame(height:245)
            if !recent.isEmpty {
                VStack(alignment:.leading,spacing:12) {
                    SectionHeading(title:"Continue listening",action:{ browse("Recent") })
                    ScrollView(.horizontal,showsIndicators:false) {
                        HStack(alignment:.top,spacing:14) {
                            ForEach(Array(recent.prefix(12))) { track in
                                Button { play(track,within:recent,source:"rail-\(track.id)") } label: {
                                    VStack(alignment:.leading,spacing:7) {
                                        artwork(track,key:"rail-\(track.id)").frame(width:108,height:108)
                                        Text(track.title).font(.caption).lineLimit(1)
                                        Text(track.artist).font(.system(size:10)).foregroundStyle(DA.silver.opacity(0.8)).lineLimit(1)
                                    }.frame(width:108,alignment:.leading)
                                }.buttonStyle(.plain).accessibilityLabel("Play \(track.title), \(track.artist)")
                            }
                        }
                    }
                }
                VStack(alignment:.leading,spacing:8) {
                    SectionHeading(title:"Recently added",action:{ browse("Songs") })
                    ForEach(Array(library.catalog.tracks.sorted { $0.added>$1.added }.prefix(4))) { row($0,context:recent) }
                }
            } else if !library.loading {
                VStack(alignment:.leading,spacing:10) {
                    Text("Your first record is waiting.").font(.system(.title2,design:.serif))
                    Text("Import DRM-free audio you already own from Files.").font(.subheadline).foregroundStyle(DA.silver)
                    Button("Import audio",systemImage:"plus") { importing=true }.font(.subheadline).padding(.vertical,12)
                }.padding(.vertical,20)
            }
            Button { withAnimation(motion) { perspective="Collection" } } label: {
                HStack(spacing:13) { Image(systemName:"square.stack"); Text("Your Collection").font(.system(.title3,design:.serif)); Spacer(); Image(systemName:"arrow.up.right").font(.caption) }
                    .padding(.vertical,18).padding(.horizontal,16).background(.white.opacity(0.025),in:RoundedRectangle(cornerRadius:18)).overlay(RoundedRectangle(cornerRadius:18).stroke(.white.opacity(0.07),lineWidth:0.5))
            }.buttonStyle(.plain)
        }
    }
    private var collectionOverview:some View {
        VStack(alignment:.leading,spacing:0) {
            pageHeader("Your Collection",back:{ withAnimation(motion) { perspective="Room" } })
            AlbumCarousel(albums:AlbumGroup.collect(recent),namespace:space,hiddenID:album?.id,initialAlbumID:services.playback.current?.albumKey) { group in openAlbum(group) }
                .padding(.vertical,2)
            collectionLink("Songs",symbol:"music.note",count:library.catalog.tracks.count) { browse("Songs") }
            collectionLink("Albums",symbol:"opticaldisc",count:Set(library.catalog.tracks.map(\.albumKey)).count) { browse("Albums") }
            collectionLink("Artists",symbol:"person.fill",count:Set(library.catalog.tracks.map(\.artist)).count) { browse("Artists") }
            collectionLink("Playlists",symbol:"list.bullet",count:library.catalog.playlists.count) { playlists=true }
            collectionLink("Favorites",symbol:"heart",count:library.catalog.tracks.filter(\.favorite).count) { browse("Favorites") }
        }
    }
    private var browser:some View {
        VStack(alignment:.leading,spacing:14) {
            pageHeader(lens,back:{ withAnimation(motion) { perspective="Collection" } })
            ScrollView(.horizontal,showsIndicators:false) { HStack(spacing:7) { ForEach(lenses,id:\.self) { name in LensChip(title:name,selected:lens==name) { withAnimation(motion) { lens=name } } } } }
            collection
        }
    }
    private var options:some View {
        Menu {
            Button("Your collection",systemImage:"square.stack") { withAnimation(motion) { perspective="Collection" } }
            Button("Playlists",systemImage:"list.bullet") { playlists=true }
            Button("Import audio",systemImage:"plus") { importing=true }
            Button("Settings & backup",systemImage:"slider.horizontal.3") { settings=true }
        } label: { Image(systemName:"slider.horizontal.3").font(.system(size:14)).frame(width:34,height:34).recordGlass(radius:20).overlay(Circle().stroke(.white.opacity(0.14),lineWidth:0.5)).frame(width:44,height:44) }.accessibilityLabel("Collection options")
    }
    private func pageHeader(_ title:String,back:@escaping ()->Void)->some View {
        RecordGlassGroup { HStack(spacing:4) {
            ChromeButton(symbol:"chevron.left",label:"Back",action:back).padding(.leading,-10)
            Text(title).font(DA.TypeScale.heading).tracking(-0.6); Spacer(minLength:0)
            ChromeButton(symbol:"magnifyingglass",label:"Search your collection",action:showSearch)
            options
        }.padding(.top,6) }
    }
    private func collectionLink(_ title:String,symbol:String,count:Int,action:@escaping ()->Void)->some View {
        Button(action:action) {
            HStack(spacing:12) {
                Image(systemName:symbol).font(.system(size:14,weight:.regular)).frame(width:18)
                Text(title).font(DA.TypeScale.navigation)
                Text("\(count)").font(.caption2).foregroundStyle(DA.silver.opacity(0.55))
                Spacer(); Image(systemName:"chevron.right").font(.system(size:11,weight:.light)).foregroundStyle(DA.silver)
            }.padding(.horizontal,10).frame(minHeight:44)
                .overlay(alignment:.bottom) { Rectangle().fill(.white.opacity(0.055)).frame(height:0.5).padding(.leading,39) }
        }.buttonStyle(.plain)
    }
    @ViewBuilder private var collection:some View {
        if lens=="Albums" {
            let groups=Dictionary(grouping:tracks,by:\.albumKey)
            LazyVGrid(columns:[GridItem(.adaptive(minimum:96),spacing:14)],spacing:22) {
                ForEach(groups.keys.sorted(),id:\.self) { key in
                    if let records=groups[key],let first=records.first {
                        Button { withAnimation(motion) { album=AlbumSelection(id:key,title:first.album=="Singles" ? first.title:first.album,artist:first.artist,tracks:records.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }) } } label: {
                            VStack(alignment:.leading,spacing:6) {
                                Cover(track:first,radius:5).matchedGeometryEffect(id:"album-\(key)",in:space,isSource:album?.id != key).opacity(album?.id==key ? 0:1)
                                Text(first.album=="Singles" ? first.title:first.album).font(.caption).lineLimit(1)
                                Text(first.artist).font(.system(size:10)).foregroundStyle(DA.silver.opacity(0.8)).lineLimit(1)
                            }
                        }.buttonStyle(.plain)
                    }
                }
            }
        } else if ["Artists","Decades","Genres"].contains(lens) {
            let groups=Dictionary(grouping:tracks) { t in lens=="Artists" ? t.artist : lens=="Genres" ? (t.genre ?? "Unclassified") : (t.year.map { "\($0/10*10)s" } ?? "Undated") }
            LazyVStack(alignment:.leading,spacing:14) { ForEach(groups.keys.sorted(),id:\.self) { key in Text(key).font(.system(.title3,design:.serif)).padding(.top,12); ForEach(groups[key] ?? []) { row($0,context:groups[key] ?? []) } } }
        } else { LazyVStack(spacing:8) { ForEach(tracks) { row($0,context:tracks) } } }
        if tracks.isEmpty { Text("Your records will appear here.").font(.subheadline).foregroundStyle(DA.silver).padding(.vertical,45) }
    }
    private func row(_ track:Track,context:[Track])->some View { RecordRow(track:track,action:{ play(track,within:context,source:"row-\(track.id)") },edit:{ editing=track },namespace:space,artworkID:"row-\(track.id)",hiddenArtwork:expanded && source=="row-\(track.id)") }
    @ViewBuilder private func artwork(_ track:Track,key:String)->some View {
        if expanded && source==key { Color.clear.aspectRatio(1,contentMode:.fit) } else { Cover(track:track,radius:5).matchedGeometryEffect(id:key,in:space) }
    }
    private func openAlbum(_ group:AlbumGroup) {
        withAnimation(motion) { album=AlbumSelection(id:group.id,title:group.title,artist:group.cover.artist,tracks:group.tracks.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }) }
    }
    private func browse(_ name:String) { withAnimation(motion) { lens=name; perspective="Browser" } }
    private func showSearch() { withAnimation(motion) { searching=true } }
    private func play(_ track:Track,within tracks:[Track],source:String) { self.source=source; services.playback.play(track,within:tracks); withAnimation(motion) { expanded=true } }
}
struct ListeningOrb:View {
    var body:some View {
        ZStack {
            Circle().fill(RadialGradient(colors:[Color(red:0.28,green:0.08,blue:0.06),.black,.clear],center:.bottomTrailing,startRadius:5,endRadius:150))
            ForEach(0..<5) { index in
                Ellipse().stroke(LinearGradient(colors:[.clear,DA.silver.opacity(0.18),Color(red:0.48,green:0.15,blue:0.12).opacity(0.25),.clear],startPoint:.topLeading,endPoint:.bottomTrailing),lineWidth:0.7)
                    .frame(width:170-CGFloat(index)*11,height:190-CGFloat(index)*7).rotationEffect(.degrees(Double(index)*28))
            }
        }
    }
}
struct AlbumExperience:View {
    let selection:AlbumSelection; let space:Namespace.ID; let playerExpanded:Bool
    let play:(Track)->Void; let close:()->Void; let edit:(Track)->Void
    var shuffle:(()->Void)?=nil
    @State private var ambient:Color = .black
    @AppStorage("ambientLighting") private var ambientLighting=true
    var body:some View {
        ZStack {
            DA.black.ignoresSafeArea()
            RadialGradient(colors:[ambient.opacity(0.28),.clear],center:.top,startRadius:20,endRadius:420).opacity(ambientLighting ? 1:0).ignoresSafeArea()
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    HStack { ChromeButton(symbol:"chevron.left",label:"Back to collection",action:close); Spacer(); Text("THE RECORD").font(.system(size:9)).tracking(2).foregroundStyle(DA.silver); Spacer(); Color.clear.frame(width:44,height:44) }
                    if let first=selection.tracks.first {
                        if playerExpanded { Color.clear.aspectRatio(1,contentMode:.fit) } else { Cover(track:first,radius:9).matchedGeometryEffect(id:"album-\(selection.id)",in:space).overlay { Color.clear.matchedGeometryEffect(id:"album-detail",in:space) } }
                        HStack(alignment:.bottom) {
                            VStack(alignment:.leading,spacing:8) { Text(selection.title).font(.system(.title,design:.serif)); Text(selection.artist).font(.subheadline).foregroundStyle(DA.silver) }; Spacer()
                            Button { play(first) } label: { Image(systemName:"play.fill").font(.title3).frame(width:58,height:58).recordGlass(radius:20).overlay(Circle().stroke(.white.opacity(0.2),lineWidth:0.5)) }.accessibilityLabel("Play album")
                        }.padding(.vertical,6)
                    }
                    if let first=selection.tracks.first {
                        HStack(spacing:24) {
                            Text("\(selection.tracks.count) \(selection.tracks.count == 1 ? "track":"tracks")").font(.caption).foregroundStyle(DA.silver)
                            Spacer(); Button { if let shuffle { shuffle() } else { play(first) } } label: { Label("Shuffle",systemImage:"shuffle").font(.caption).frame(minHeight:44) }
                        }
                    }
                    Divider().overlay(.white.opacity(0.04))
                    ForEach(selection.tracks) { track in RecordRow(track:track,action:{ play(track) },edit:{ edit(track) }) }
                }.padding(.horizontal,22).padding(.bottom,24)
            }
        }.foregroundStyle(DA.ivory).tint(DA.ivory).task(id:selection.id) {
            if let first=selection.tracks.first { _=await ArtworkCache.image(first); ambient=ArtworkCache.color(first) }
        }
    }
}
