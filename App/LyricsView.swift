import SwiftUI
import UniformTypeIdentifiers
import DigitalAnalogCore

struct PlayerDrawer:View {
    let track:Track; let initial:String
    @State private var section="Queue"
    var body:some View {
        VStack(spacing:0) {
            Picker("Player layer",selection:$section) { Text("Queue").tag("Queue"); Text("Lyrics").tag("Lyrics") }.pickerStyle(.segmented).padding(.horizontal,22).padding(.top,24).padding(.bottom,8)
            if section=="Queue" { QueueView() } else { LyricsView(track:track) }
        }.background(DA.black).onAppear { section=initial }.tint(DA.ivory).preferredColorScheme(.dark)
    }
}
struct LyricsView:View {
    let track:Track
    @EnvironmentObject private var library:Library
    @EnvironmentObject private var playback:Playback
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var editing=false
    @State private var draft=""
    @State private var importing=false
    @State private var error:String?
    private var saved:String { library.catalog.tracks.first { $0.id==track.id }?.lyrics ?? "" }
    var body:some View {
        NavigationStack {
            Group {
                if editing {
                    TextEditor(text:$draft).font(.body).scrollContentBackground(.hidden).padding(18).accessibilityLabel("Lyrics text or LRC")
                } else if saved.isEmpty {
                    VStack(spacing:17) {
                        Image(systemName:"text.alignleft").font(.system(size:30,weight:.ultraLight)).foregroundStyle(DA.silver)
                        Text("Words to keep.").font(.system(.title2,design:.serif))
                        Text("Import a text or LRC file, or paste lyrics you’re allowed to store. They stay available offline.").font(.subheadline).foregroundStyle(DA.silver).multilineTextAlignment(.center)
                        Button("Add lyrics") { draft=saved; editing=true }.padding(.top,8)
                        Button("Import from Files") { importing=true }.font(.subheadline)
                    }.padding(32).frame(maxWidth:.infinity,maxHeight:.infinity)
                } else { lyricLines }
            }.background(DA.black).navigationTitle("Lyrics").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement:.topBarLeading) { Button("Done") { dismiss() } }
                    ToolbarItem(placement:.topBarTrailing) {
                        if editing { Button("Save") { save() } }
                        else { Menu { Button("Edit") { draft=saved;editing=true }; Button("Import from Files") { importing=true } } label: { Image(systemName:"ellipsis") }.accessibilityLabel("Lyrics actions") }
                    }
                }
                .fileImporter(isPresented:$importing,allowedContentTypes:[.plainText,.text,UTType(filenameExtension:"lrc") ?? .text]) { result in
                    do {
                        let url=try result.get();let access=url.startAccessingSecurityScopedResource();defer { if access { url.stopAccessingSecurityScopedResource() } }
                        let data=try Data(contentsOf:url);guard data.count<1_000_000,let text=String(data:data,encoding:.utf8) else { throw AppFailure.message("Choose a UTF-8 text or LRC file smaller than 1 MB.") }
                        draft=text;editing=true
                    } catch { self.error=error.localizedDescription }
                }
                .alert("Lyrics",isPresented:Binding(get:{error != nil},set:{if !$0 {error=nil}})) { Button("OK") { error=nil } } message: { Text(error ?? "") }
        }.foregroundStyle(DA.ivory).tint(DA.ivory).preferredColorScheme(.dark)
    }
    private var lyricLines:some View {
        let document=LyricsDocument(saved);let active=document.activeID(at:playback.position)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment:.leading,spacing:22) {
                    ForEach(document.lines) { line in
                        Text(line.text.isEmpty ? "···":line.text).font(.system(.title2,design:.serif))
                            .foregroundStyle(!document.synchronized || line.id==active ? DA.ivory:DA.silver.opacity(0.5)).id(line.id)
                    }
                }.padding(26)
            }.onChange(of:active) { _,id in if let id { withAnimation(reduceMotion ? nil:.easeInOut(duration:0.25)) { proxy.scrollTo(id,anchor:.center) } } }
        }
    }
    private func save() {
        guard var current=library.catalog.tracks.first(where:{$0.id==track.id}) else { return }
        current.lyrics=draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? nil:draft
        library.update(current); editing=false
    }
}
