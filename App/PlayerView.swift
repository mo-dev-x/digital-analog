import SwiftUI
import DigitalAnalogCore
import AVKit

struct PlayerView:View {
    let track:Track
    let namespace:Namespace.ID
    let artworkID:String
    let dismiss:()->Void
    @EnvironmentObject var playback:Playback
    @EnvironmentObject var library:Library
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState(resetTransaction:Transaction(animation:DA.spring)) private var drag:CGFloat=0
    @AppStorage("ambientLighting") private var ambientLighting=true
    @State private var ambient:Color = .black
    @State private var queue=false
    @State private var drawerSection="Queue"
    @State private var editing=false
    @State private var scrubbing=false
    @State private var scrub:Double=0
    private var favorite:Bool { library.catalog.tracks.first { $0.id==track.id }?.favorite ?? false }
    private var dismissal:some Gesture {
        DragGesture().updating($drag) { value,state,_ in state=max(0,value.translation.height) }.onEnded { value in
            if value.translation.height>90 || (value.translation.height>40 && value.predictedEndTranslation.height>180) { dismiss() }
        }
    }
    var body:some View {
        GeometryReader { geometry in
            let coverWidth=min(geometry.size.width-80,max(210,geometry.size.height*0.34),310)
            ZStack {
                DA.black.opacity(1-min(drag/600,0.7)).ignoresSafeArea()
                RadialGradient(colors:[ambient.opacity(0.48),.clear],center:.init(x:0.5,y:0.27),startRadius:0,endRadius:geometry.size.width*0.8).opacity(ambientLighting ? 1:0).ignoresSafeArea()
                ScrollView(showsIndicators:false) {
                    VStack(spacing:0) {
                        Capsule().fill(DA.silver.opacity(0.4)).frame(width:36,height:4)
                            .frame(maxWidth:.infinity).frame(height:44).contentShape(Rectangle())
                            .highPriorityGesture(dismissal.exclusively(before:TapGesture().onEnded { _ in dismiss() }))
                            .accessibilityElement().accessibilityAddTraits(.isButton)
                            .accessibilityIdentifier("player-dismiss").accessibilityLabel("Back to collection")
                            .accessibilityAction { dismiss() }
                        Cover(track:track,radius:9).matchedGeometryEffect(id:artworkID,in:namespace)
                            .frame(width:coverWidth,height:coverWidth)
                            .overlay(RoundedRectangle(cornerRadius:9).stroke(.white.opacity(0.19),lineWidth:0.5))
                            .shadow(color:ambient.opacity(0.15),radius:40,y:15).shadow(color:.black.opacity(0.55),radius:20,y:14)
                            .padding(.top,18).padding(.bottom,28).accessibilityIdentifier("player-artwork").gesture(dismissal)
                        VStack(spacing:12) {
                            HStack(spacing:12) {
                                VStack(alignment:.leading,spacing:7) {
                                    Text(track.title).font(DA.TypeScale.playerTitle).fixedSize(horizontal:false,vertical:true)
                                    Text(track.artist).font(DA.TypeScale.metadata).foregroundStyle(DA.silver.opacity(0.8))
                                }; Spacer(minLength:0)
                                Button { library.toggleFavorite(track.id); UISelectionFeedbackGenerator().selectionChanged() } label: { Image(systemName:favorite ? "heart.fill":"heart").font(.system(size:20,weight:.light)).frame(width:44,height:44) }.accessibilityLabel(favorite ? "Remove favorite":"Favorite")
                            }
                            VStack(spacing:0) {
                                NativeScrubber(value:Binding(get:{ scrubbing ? scrub:min(playback.position,max(track.duration,1)) },set:{ scrub=$0 }),duration:max(track.duration,1)) { active in
                                    if active { scrub=playback.position; scrubbing=true } else { playback.seek(scrub); scrubbing=false }
                                }.frame(height:44)
                                HStack { Text(time(scrubbing ? scrub:playback.position)); Spacer(); Text("−"+time(max(0,track.duration-(scrubbing ? scrub:playback.position)))) }.font(.system(.caption2,design:.monospaced)).foregroundStyle(DA.silver.opacity(0.7))
                            }
                            HStack(spacing:0) {
                                Button { playback.setShuffle(!playback.shuffle) } label: { Image(systemName:"shuffle").font(.system(size:16)).foregroundStyle(playback.shuffle ? DA.ivory:DA.silver.opacity(0.6)).frame(width:44,height:44) }.accessibilityLabel(playback.shuffle ? "Shuffle on":"Shuffle off")
                                Spacer(minLength:3)
                                Button { playback.previous() } label: { Image(systemName:"backward.end.fill").font(.system(size:21)).frame(width:44,height:44) }.accessibilityLabel("Previous track")
                                Spacer(minLength:8)
                                Button { playback.toggle(); UIImpactFeedbackGenerator(style:.soft).impactOccurred() } label: {
                                    ZStack {
                                        Circle().fill(.ultraThinMaterial)
                                        Circle().fill(LinearGradient(colors:[.white.opacity(0.06),.clear,.white.opacity(0.03)],startPoint:.topLeading,endPoint:.bottomTrailing))
                                        Circle().stroke(LinearGradient(colors:[.white.opacity(0.32),.white.opacity(0.08)],startPoint:.topLeading,endPoint:.bottomTrailing),lineWidth:0.7)
                                        if playback.buffering { ProgressView().tint(DA.ivory) } else { Image(systemName:playback.playing ? "pause.fill":"play.fill").font(.system(size:23,weight:.regular)).offset(x:playback.playing ? 0:2) }
                                    }.frame(width:60,height:60).shadow(color:ambient.opacity(0.12),radius:18)
                                }.accessibilityLabel(playback.playing ? "Pause":"Play")
                                Spacer(minLength:8)
                                Button { playback.next() } label: { Image(systemName:"forward.end.fill").font(.system(size:21)).frame(width:44,height:44) }.accessibilityLabel("Next track")
                                Spacer(minLength:3)
                                Button { playback.cycleRepeat() } label: { Image(systemName:playback.repeatMode==2 ? "repeat.1":"repeat").font(.system(size:16)).foregroundStyle(playback.repeatMode==0 ? DA.silver.opacity(0.6):DA.ivory).frame(width:44,height:44) }.accessibilityLabel(["Repeat off","Repeat queue","Repeat song"][playback.repeatMode])
                            }.frame(maxWidth:300).padding(.top,3)
                            HStack {
                                Image(systemName:"checkmark.circle").frame(width:44,height:44).foregroundStyle(DA.silver).accessibilityLabel("Available offline")
                                Spacer(); RoutePicker().frame(width:44,height:44).accessibilityLabel("Audio output"); Spacer()
                                Button { drawerSection="Queue"; queue=true } label: { Image(systemName:"list.bullet").frame(width:44,height:44) }.accessibilityLabel("Open queue")
                                Spacer()
                                Menu {
                                    Button("Edit record",systemImage:"pencil") { editing=true }
                                    Menu("Add to playlist") { ForEach(library.catalog.playlists) { list in Button(list.name) { library.addToPlaylist(track.id,playlist:list.id) } } }
                                } label: { Image(systemName:"ellipsis").frame(width:44,height:44) }.accessibilityLabel("Record actions")
                            }.font(.system(size:17,weight:.light)).padding(.top,8)
                            VStack(spacing:3) {
                                Capsule().fill(.white.opacity(0.15)).frame(width:24,height:3).padding(.top,6)
                                HStack {
                                    Button { drawerSection="Lyrics";queue=true } label: { Text("Lyrics").font(.subheadline).frame(minHeight:38) }
                                    Spacer()
                                    Button { drawerSection="Queue";queue=true } label: { Label("Queue",systemImage:"list.bullet").font(.caption).frame(minHeight:38) }
                                }.padding(.horizontal,15)
                            }.background(.white.opacity(0.025),in:RoundedRectangle(cornerRadius:15))
                                .overlay(RoundedRectangle(cornerRadius:15).stroke(.white.opacity(0.06),lineWidth:0.5))
                        }.padding(.horizontal,26)
                    }.padding(.bottom,18)
                }
            }.offset(y:reduceMotion ? 0:drag).scaleEffect(reduceMotion ? 1:1-min(drag/1800,0.12))
        }.foregroundStyle(DA.ivory).tint(DA.ivory).preferredColorScheme(.dark)
            .task(id:"\(track.id)|\(track.artwork ?? "")") { _=await ArtworkCache.image(track); withAnimation(reduceMotion ? nil:.easeInOut(duration:0.7)) { ambient=ArtworkCache.color(track) } }
            .sheet(isPresented:$queue) { PlayerDrawer(track:track,initial:drawerSection).presentationDetents([.medium,.large]).presentationDragIndicator(.visible).presentationBackground(DA.black) }.sheet(isPresented:$editing) { TrackEditor(track:track) }
    }
    private func time(_ seconds:Double)->String { let s=Int(max(0,seconds.isFinite ? seconds:0)); return String(format:"%d:%02d",s/60,s%60) }
}
/// A native slider keeps seeking, VoiceOver and the 44pt interaction area while
/// using the reference's quiet hairline track and small thumb.
struct NativeScrubber:UIViewRepresentable {
    @Binding var value:Double
    let duration:Double
    let editing:(Bool)->Void
    func makeCoordinator()->Coordinator { Coordinator(self) }
    func makeUIView(context:Context)->UISlider {
        let slider=UISlider(); slider.minimumValue=0
        slider.minimumTrackTintColor=UIColor(DA.ivory).withAlphaComponent(0.8)
        slider.maximumTrackTintColor=UIColor.white.withAlphaComponent(0.16)
        let image=UIGraphicsImageRenderer(size:CGSize(width:8,height:8)).image { ctx in UIColor(DA.ivory).setFill(); ctx.cgContext.fillEllipse(in:CGRect(x:0,y:0,width:8,height:8)) }
        slider.setThumbImage(image,for:.normal); slider.setThumbImage(image,for:.highlighted)
        slider.addTarget(context.coordinator,action:#selector(Coordinator.change(_:)),for:.valueChanged)
        slider.addTarget(context.coordinator,action:#selector(Coordinator.begin),for:.touchDown)
        slider.addTarget(context.coordinator,action:#selector(Coordinator.end),for:[.touchUpInside,.touchUpOutside,.touchCancel])
        slider.accessibilityLabel="Playback position"; return slider
    }
    func updateUIView(_ slider:UISlider,context:Context) {
        context.coordinator.parent=self; slider.maximumValue=Float(duration)
        if !slider.isTracking { slider.value=Float(value) }
    }
    final class Coordinator:NSObject {
        var parent:NativeScrubber
        init(_ parent:NativeScrubber) { self.parent=parent }
        @objc func begin() { parent.editing(true) }
        @objc func end() { parent.editing(false) }
        @objc func change(_ slider:UISlider) {
            // VoiceOver changes have no touch-down/up pair.
            if !slider.isTracking { parent.editing(true) }
            parent.value=Double(slider.value)
            if !slider.isTracking { parent.editing(false) }
        }
    }
}
struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView { let v = AVRoutePickerView(); v.tintColor = .white; v.activeTintColor = .lightGray; return v }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) { }
}
struct QueueView:View {
    @EnvironmentObject var library:Library
    @EnvironmentObject var playback:Playback
    @Environment(\.dismiss) private var dismiss
    private var tracks:[Track] {
        let lookup=Dictionary(uniqueKeysWithValues:library.catalog.tracks.map { ($0.id,$0) })
        return playback.queue.compactMap { lookup[$0] }
    }
    var body:some View {
        NavigationStack {
            List {
                ForEach(tracks) { track in
                    QueueRecordRow(track:track,current:playback.current?.id==track.id) { playback.playQueued(track.id) }
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top:5,leading:16,bottom:5,trailing:16))
                }.onMove(perform:move).onDelete(perform:remove)
            }.listStyle(.plain).scrollContentBackground(.hidden).background(DA.black)
                .navigationTitle("Queue").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement:.topBarLeading) { Button("Done") { dismiss() } }
                    ToolbarItem(placement:.topBarTrailing) { EditButton() }
                }
        }.preferredColorScheme(.dark).foregroundStyle(DA.ivory).tint(DA.ivory)
    }
    private func move(from:IndexSet,to:Int) { var order=playback.queue; order.move(fromOffsets:from,toOffset:to); playback.reorderQueue(order) }
    private func remove(at offsets:IndexSet) { let ids=offsets.map { tracks[$0].id }; ids.forEach { playback.removeFromQueue($0) } }
}
private struct QueueRecordRow:View {
    let track:Track; let current:Bool; let action:()->Void
    var body:some View {
        Button(action:action) {
            HStack(spacing:12) {
                Cover(track:track,radius:5).frame(width:46,height:46)
                VStack(alignment:.leading,spacing:5) { Text(track.title).font(.subheadline); Text(track.artist).font(.caption).foregroundStyle(DA.silver) }
                Spacer(); if current { Image(systemName:"waveform").font(.caption) }
            }.padding(.horizontal,8)
                .background(current ? .white.opacity(0.045):.clear,in:RoundedRectangle(cornerRadius:12))
        }.buttonStyle(.plain)
    }
}
