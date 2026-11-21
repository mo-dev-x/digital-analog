import SwiftUI
import os
import DigitalAnalogCore

struct AlbumGroup:Identifiable,Equatable {
    let id:String; let tracks:[Track]
    var cover:Track { tracks[0] }
    var title:String { cover.album=="Singles" ? cover.title:cover.album }
    static func collect(_ tracks:[Track])->[AlbumGroup] {
        var order:[String]=[]; var groups:[String:[Track]]=[:]
        for track in tracks { if groups[track.albumKey]==nil { order.append(track.albumKey) }; groups[track.albumKey,default:[]].append(track) }
        return order.compactMap { id in groups[id].map { AlbumGroup(id:id,tracks:$0) } }
    }
}
enum CollectionStudy:String,CaseIterable { case orbit,fan,shelf }
struct AlbumCarousel:View {
    var study:CollectionStudy = .orbit
    let albums:[AlbumGroup]
    let namespace:Namespace.ID
    let hiddenID:String?
    var initialAlbumID:String?=nil
    let open:(AlbumGroup)->Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("ambientLighting") private var ambientLighting=true
    @State private var ambient:Color = .black
    @State private var focus=AlbumFocus(ids:[])
    @GestureState(resetTransaction:Transaction(animation:DA.spring)) private var drag:CGFloat=0
    @State private var lookup:[String:AlbumGroup]=[:]
    private var selected:AlbumGroup? { focus.selected.flatMap { lookup[$0] } ?? albums.first }
    private var motion:Animation? { reduceMotion ? nil:DA.spring }
    private var visible:[AlbumGroup] {
        return focus.window().compactMap { lookup[$0] }
    }
    var body:some View {
        VStack(spacing:4) {
            GeometryReader { geometry in
                ZStack {
                    if let selected {
                        Circle().fill(RadialGradient(colors:[ambient.opacity(0.32),.clear],center:.center,startRadius:5,endRadius:150)).frame(width:290,height:230).offset(y:5).opacity(ambientLighting ? 1:0)
                        ForEach(Array(visible.enumerated()),id:\.element.id) { index,album in
                            albumButton(album,index:index,width:geometry.size.width)
                        }
                    } else { Text("Your albums will live here.").font(.caption).foregroundStyle(DA.silver).frame(maxWidth:.infinity,maxHeight:.infinity) }
                }.contentShape(Rectangle())
                    .simultaneousGesture(DragGesture(minimumDistance:18).updating($drag) { value,state,_ in
                        if abs(value.translation.width)>abs(value.translation.height) { state=value.translation.width }
                    }.onEnded { value in
                        guard abs(value.translation.width)>abs(value.translation.height) else { return }
                        if abs(value.predictedEndTranslation.width)>45 { step(value.predictedEndTranslation.width<0 ? 1:-1) }
                    })
            }.frame(height:245)
            HStack(spacing:10) {
                ChromeButton(symbol:"chevron.left",label:"Previous album") { step(-1) }.disabled(albums.count<2)
                VStack(spacing:3) {
                    Text(selected?.title ?? "Collection").font(.subheadline).lineLimit(1)
                    Text(selected?.cover.artist ?? "").font(.caption2).foregroundStyle(DA.silver).lineLimit(1)
                }.frame(maxWidth:.infinity).accessibilityElement(children:.combine)
                ChromeButton(symbol:"chevron.right",label:"Next album") { step(1) }.disabled(albums.count<2)
            }
        }.onAppear { reload() }.onChange(of:albums) { _,_ in reload() }
            .task(id:selected?.id) {
                guard let selected else { return };_=await ArtworkCache.image(selected.cover)
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? nil:.easeInOut(duration:0.45)) { ambient=ArtworkCache.color(selected.cover) }
            }
            .accessibilityScrollAction { edge in if edge == .leading { step(-1) } else if edge == .trailing { step(1) } }
    }
    private func albumButton(_ album:AlbumGroup,index:Int,width:CGFloat)->some View {
        let offset=index==0 ? 0:(index%2==1 ? -(index+1)/2:index/2)
        let central=index==0
        let phase=CGFloat(offset)+(reduceMotion ? 0:min(1,max(-1,drag/max(width*0.62,1))))
        let distance=min(abs(phase),2)
        let diameter:CGFloat=184-distance*48
        let angle=Double(phase)*0.92
        let x:CGFloat=width/2+CGFloat(sin(angle))*max(0,width/2-48)
        let y:CGFloat=study == .orbit ? 135-CGFloat(1-cos(angle))*72:135+distance*12
        let placementX:CGFloat=study == .shelf ? width/2+phase*105:x
        return Button {
            if central { open(album) } else { withAnimation(motion) { focus.select(album.id) } }
        } label: {
            albumSleeve(album,central:central,diameter:diameter)
        }.buttonStyle(.plain).rotation3DEffect(.degrees(study == .fan ? Double(phase)*(-24):Double(phase)*(-8)),axis:(x:0,y:1,z:0),perspective:0.35)
            .position(x:placementX,y:y)
            .zIndex(Double(3-distance)).opacity(1-Double(distance)*0.12)
            .accessibilityIdentifier(central ? "focused-album":"neighbor-\(album.id)")
            .accessibilityLabel(central ? "Open \(album.title), \(album.cover.artist)":"Focus \(album.title), \(album.cover.artist)")
    }
    private func albumSleeve(_ album:AlbumGroup,central:Bool,diameter:CGFloat)->some View {
        ZStack {
            Circle().fill(.black)
            Cover(track:album.cover,radius:5)
                .matchedGeometryEffect(id:"album-\(album.id)",in:namespace,isSource:hiddenID != album.id)
                .frame(width:diameter,height:diameter).clipShape(Circle())
                .opacity(hiddenID==album.id ? 0:1)
            Circle().fill(LinearGradient(colors:[.white.opacity(central ? 0.12:0.07),.clear,.black.opacity(0.22)],startPoint:.topLeading,endPoint:.bottomTrailing)).allowsHitTesting(false)
            Circle().stroke(LinearGradient(colors:[.white.opacity(central ? 0.3:0.12),.clear,.white.opacity(0.07)],startPoint:.topLeading,endPoint:.bottomTrailing),lineWidth:0.6)
        }.frame(width:diameter,height:diameter).shadow(color:.black.opacity(0.7),radius:14,y:9)
    }
    private func reload() { lookup=Dictionary(uniqueKeysWithValues:albums.map { ($0.id,$0) });if focus.ids.isEmpty { focus=AlbumFocus(ids:albums.map(\.id),selected:initialAlbumID) } else { focus.reconcile(albums.map(\.id)) } }
    private func step(_ delta:Int) {
        let log=OSLog(subsystem:"personal.digitalanalog",category:"Navigation")
        let signpost=OSSignpostID(log:log)
        os_signpost(.begin,log:log,name:"AlbumFocus",signpostID:signpost,"isAnimation=YES")
        withAnimation(motion,completionCriteria:.logicallyComplete) { focus.advance(delta) } completion: {
            os_signpost(.end,log:log,name:"AlbumFocus",signpostID:signpost)
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
