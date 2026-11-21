import SwiftUI
import DigitalAnalogCore

enum DA {
    static let black=Color(red:5/255,green:5/255,blue:5/255)
    static let surface=Color(red:20/255,green:20/255,blue:20/255)
    static let ivory=Color(red:245/255,green:243/255,blue:239/255)
    static let silver=Color(red:185/255,green:179/255,blue:167/255)
    enum TypeScale {
        static let heading=Font.system(.title2,design:.serif)
        static let playerTitle=Font.system(.title2,design:.serif)
        static let navigation=Font.system(.subheadline)
        static let metadata=Font.system(.caption)
    }
    static let spring=Animation.spring(response:0.48,dampingFraction:0.86)
}
struct ChromeButton:View {
    let symbol:String; let label:String; let action:()->Void
    var body:some View {
        Button(action:action) {
            Image(systemName:symbol).font(.system(size:14,weight:.regular))
                .frame(width:32,height:32).recordGlass(radius:16)
                .overlay(Circle().stroke(.white.opacity(0.12),lineWidth:0.5)).frame(width:44,height:44).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(DA.ivory).accessibilityLabel(label)
    }
}
struct LensChip:View {
    let title:String; let selected:Bool; let action:()->Void
    var body:some View {
        Button(action:action) {
            Text(title).font(.caption).foregroundStyle(selected ? DA.ivory:DA.silver)
                .padding(.horizontal,15).padding(.vertical,8)
                .background(selected ? .white.opacity(0.23):.white.opacity(0.035),in:RoundedRectangle(cornerRadius:9))
                .frame(minHeight:44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected:[])
    }
}
struct SectionHeading:View {
    let title:String; var action:(()->Void)?=nil
    var body:some View {
        HStack {
            Text(title).font(.subheadline.weight(.medium)); Spacer()
            if let action { Button(action:action) { Image(systemName:"arrow.right").font(.subheadline).foregroundStyle(DA.silver).frame(width:44,height:44) }.accessibilityLabel("Show \(title)") }
        }.frame(minHeight:32)
    }
}
struct RecordRow:View {
    let track:Track
    let action:()->Void
    let edit:()->Void
    var namespace:Namespace.ID?=nil
    var artworkID:String?=nil
    var hiddenArtwork=false
    @EnvironmentObject private var library:Library
    var body:some View {
        HStack(spacing:8) {
            Button(action:action) {
                HStack(spacing:12) {
                    rowCover.frame(width:46,height:46)
                    VStack(alignment:.leading,spacing:4) {
                        Text(track.title).font(.subheadline).foregroundStyle(DA.ivory).lineLimit(1)
                        Text(track.artist).font(.caption).foregroundStyle(DA.silver.opacity(0.8)).lineLimit(1)
                    }; Spacer(minLength:2)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            Menu {
                Button(track.favorite ? "Remove favorite":"Favorite",systemImage:track.favorite ? "heart.slash":"heart") { library.toggleFavorite(track.id) }
                Button("Edit record",systemImage:"pencil",action:edit)
                Menu("Add to playlist") { ForEach(library.catalog.playlists) { list in Button(list.name) { library.addToPlaylist(track.id,playlist:list.id) } } }
                Button("Remove from collection",systemImage:"trash",role:.destructive) { library.removeTrack(track) }
            } label: { Image(systemName:"ellipsis").rotationEffect(.degrees(90)).font(.caption).frame(width:44,height:44).foregroundStyle(DA.silver) }.accessibilityLabel("Actions for \(track.title)")
        }.padding(.vertical,3)
    }
    @ViewBuilder private var rowCover:some View {
        if hiddenArtwork { Color.clear.aspectRatio(1,contentMode:.fit) }
        else if let namespace,let artworkID { Cover(track:track,radius:5).matchedGeometryEffect(id:artworkID,in:namespace) }
        else { Cover(track:track,radius:5) }
    }
}
struct CompactPlayer:View {
    @EnvironmentObject var playback:Playback
    let namespace:Namespace.ID
    let open:()->Void
    var body:some View {
        if let track=playback.current {
            HStack(spacing:8) {
                Button(action:open) {
                    HStack(spacing:11) {
                        Cover(track:track,radius:8).frame(width:34,height:34).matchedGeometryEffect(id:"compact",in:namespace)
                        VStack(alignment:.leading,spacing:3) { Text(track.title).font(.caption.weight(.medium)).lineLimit(1); Text(track.artist).font(.caption2).foregroundStyle(DA.silver).lineLimit(1) }; Spacer()
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Open player for \(track.title)")
                Button { playback.toggle() } label: {
                    ZStack {
                        Circle().fill(.white.opacity(0.08)).frame(width:30,height:30)
                        if playback.buffering { ProgressView().tint(DA.ivory) } else { Image(systemName:playback.playing ? "pause.fill":"play.fill").font(.system(size:13,weight:.semibold)) }
                    }.frame(width:44,height:44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(playback.playing ? "Pause":"Play")
            }.padding(.leading,9).padding(.trailing,5).padding(.vertical,3)
                .recordGlass(radius:25)
                .background(DA.black.opacity(0.8),in:RoundedRectangle(cornerRadius:25))
                .overlay(RoundedRectangle(cornerRadius:25).stroke(LinearGradient(colors:[.white.opacity(0.12),.white.opacity(0.035)],startPoint:.topLeading,endPoint:.bottomTrailing),lineWidth:0.6))
                .shadow(color:.black.opacity(0.8),radius:5,y:2).foregroundStyle(DA.ivory).tint(DA.ivory)
        }
    }
}

/// System-rendered optics, touch response and accessibility adaptation on iOS 26.
/// Earlier systems retain the same silhouette using native Material.
struct RecordGlass:ViewModifier {
    var radius:CGFloat=24
    var interactive=true
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder func body(content:Content)->some View {
        if reduceTransparency { content.background(DA.surface,in:RoundedRectangle(cornerRadius:radius)) }
        else if #available(iOS 26.0,*) { content.glassEffect(.regular.interactive(interactive),in:RoundedRectangle(cornerRadius:radius)) }
        else { content.background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:radius)) }
    }
}
extension View {
    func recordGlass(radius:CGFloat=24,interactive:Bool=true)->some View { modifier(RecordGlass(radius:radius,interactive:interactive)) }
}
/// A real SwiftUI layout: orbit size and spacing adapt to the available bounds
/// and the number of records, rather than positioning a fixed set of demo covers.
struct OrbitLayout:Layout {
    func sizeThatFits(proposal:ProposedViewSize,subviews:Subviews,cache:inout ())->CGSize {
        CGSize(width:proposal.width ?? 340,height:proposal.height ?? 310)
    }
    func placeSubviews(in bounds:CGRect,proposal:ProposedViewSize,subviews:Subviews,cache:inout ()) {
        let scale=min(bounds.width/340,bounds.height/310)
        for (index,view) in subviews.enumerated() {
            if index==0 {
                let size=164*scale
                view.place(at:CGPoint(x:bounds.midX-18*scale,y:bounds.midY),anchor:.center,proposal:ProposedViewSize(width:size,height:size))
            } else {
                let count=max(1,subviews.count-1)
                let angle = -Double.pi/2+Double(index-1)*2*Double.pi/Double(count)
                let size=(index%2==0 ? 70.0:83.0)*scale
                let point=CGPoint(x:bounds.midX+CGFloat(cos(angle))*124*scale,y:bounds.midY+CGFloat(sin(angle))*116*scale)
                view.place(at:point,anchor:.center,proposal:ProposedViewSize(width:size,height:size))
            }
        }
    }
}

struct RecordGlassGroup<Content:View>:View {
    private let content:Content
    init(@ViewBuilder content:()->Content) { self.content=content() }
    @ViewBuilder var body:some View {
        if #available(iOS 26.0,*) { GlassEffectContainer(spacing:12) { content } }
        else { content }
    }
}
