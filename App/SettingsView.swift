import SwiftUI
import UniformTypeIdentifiers

private struct ExportItem:Identifiable { let id=UUID(); let url:URL }
struct SettingsView:View {
    @EnvironmentObject private var library:Library
    @Environment(\.dismiss) private var dismiss
    @State private var busy=false
    @State private var status:String?
    @State private var exporter:ExportItem?
    @State private var importing=false
    @AppStorage("ambientLighting") private var ambientLighting=true
    @State private var storage="Calculating…"
    var body:some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:12) {
                    ZStack(alignment:.bottomLeading) {
                        if let record=library.catalog.tracks.first {
                            Cover(track:record,radius:6).frame(width:200,height:200).opacity(0.6)
                                .mask(LinearGradient(colors:[.black,.clear],startPoint:.topTrailing,endPoint:.bottomLeading))
                                .frame(maxWidth:.infinity,alignment:.trailing).accessibilityHidden(true)
                        }
                        VStack(alignment:.leading,spacing:8) {
                            Text("Make it yours.").font(.system(.title,design:.serif))
                            Text("Your music. Your atmosphere.").font(.caption).foregroundStyle(DA.silver)
                        }.padding(.bottom,15)
                    }.frame(height:230).padding(.bottom,8)
                    settingSurface {
                        Toggle(isOn:$ambientLighting) { Label("Artwork lighting",systemImage:"sparkles") }.tint(DA.silver)
                    }
                    settingSurface { HStack { Label("Motion",systemImage:"circle.dotted"); Spacer(); Text("Follows iPhone").font(.caption).foregroundStyle(DA.silver) } }
                    settingSurface { HStack { Label("Storage",systemImage:"internaldrive"); Spacer(); Text(storage).font(.caption).foregroundStyle(DA.silver) } }
                    settingSurface { Button { Task { await export() } } label: { Label("Export collection backup",systemImage:"square.and.arrow.up").frame(maxWidth:.infinity,alignment:.leading) }.disabled(busy) }
                    settingSurface { Button { importing=true } label: { Label("Restore a backup",systemImage:"arrow.clockwise").frame(maxWidth:.infinity,alignment:.leading) }.disabled(busy) }
                    if busy { ProgressView("Working…").tint(DA.silver).font(.caption).padding(12) }
                    if let status { Text(status).font(.caption).foregroundStyle(DA.silver).padding(.horizontal,12) }
                    settingSurface {
                        DisclosureGroup {
                            VStack(alignment:.leading,spacing:18) {
                                Text("\(library.catalog.tracks.count) records · \(library.catalog.playlists.count) playlists").font(.caption).foregroundStyle(DA.silver)
                                Button("Find missing album artwork") { Task { busy=true; defer { busy=false }; do { let count=try await library.recoverArtwork(); status="Updated \(count) covers. Existing artwork was kept." } catch { status=error.localizedDescription } } }.disabled(busy)
                                Button("Check collection integrity") { Task { await integrity() } }.disabled(busy)
                            }.padding(.top,16)
                        } label: { Label("Advanced",systemImage:"slider.horizontal.3") }
                    }
                    settingSurface {
                        DisclosureGroup {
                            VStack(alignment:.leading,spacing:15) {
                                Text("No telemetry. No media server. No subscriptions.").font(.caption).foregroundStyle(DA.silver)
                                Text("Free personal signing needs renewal. Keep a backup before changing installation methods.").font(.caption).foregroundStyle(DA.silver)
                                Link("SideStore setup",destination:URL(string:"https://docs.sidestore.io/docs/installation/prerequisites")!)
                                Link("AltStore refresh",destination:URL(string:"https://faq.altstore.io/altstore-classic/remote-altservers")!)
                                Link("MusicBrainz & Cover Art Archive",destination:URL(string:"https://musicbrainz.org/doc/Cover_Art_Archive")!)
                                Text("Plays music you import from Files. Dependency notices are included with the source; artwork rights remain with their owners.").font(.caption).foregroundStyle(DA.silver)
                            }.padding(.top,16)
                        } label: { Label("About & installation",systemImage:"info.circle") }
                    }
                }.padding(.horizontal,22).padding(.bottom,30)
            }.background(DA.black).navigationTitle("Settings").navigationBarTitleDisplayMode(.inline).toolbar { Button("Done") { dismiss() } }
                .sheet(item:$exporter) { ExportPicker(url:$0.url) }
                .fileImporter(isPresented:$importing,allowedContentTypes:[.folder]) { result in
                    Task {
                        busy=true; defer { busy=false }
                        do { let url=try result.get(); let access=url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }; try await library.restoreBackup(url); status="Backup restored. Your existing records were preserved." }
                        catch { status=error.localizedDescription }
                    }
                }
                .task {
                    let bytes=await Task.detached(priority:.utility) { ()->Int64 in
                        let keys:[URLResourceKey]=[.fileSizeKey,.isRegularFileKey]
                        guard let enumerator=FileManager.default.enumerator(at:Disk.root,includingPropertiesForKeys:keys) else { return 0 }
                        var total:Int64=0
                        for case let url as URL in enumerator { if let value=try? url.resourceValues(forKeys:Set(keys)),value.isRegularFile==true { total += Int64(value.fileSize ?? 0) } }
                        return total
                    }.value
                    storage=ByteCountFormatter.string(fromByteCount:bytes,countStyle:.file)
                }
        }.preferredColorScheme(.dark).foregroundStyle(DA.ivory).tint(DA.ivory)
    }
    private func settingSurface<Content:View>(@ViewBuilder content:()->Content)->some View {
        content().font(.subheadline).padding(.horizontal,16).padding(.vertical,11)
            .frame(maxWidth:.infinity,minHeight:46,alignment:.leading)
            .background(.white.opacity(0.018),in:RoundedRectangle(cornerRadius:12))
            .overlay(RoundedRectangle(cornerRadius:12).stroke(.white.opacity(0.07),lineWidth:0.5))
    }
    private func export() async {
        busy=true; defer { busy=false }
        do { exporter=ExportItem(url:try await library.export()); status="Choose a safe location for your backup folder." } catch { status=error.localizedDescription }
    }
    private func integrity() async {
        busy=true; defer { busy=false }
        do { let healthy=try await library.store?.integrityCheck() ?? false; let missing=library.catalog.tracks.filter { !FileManager.default.fileExists(atPath:Disk.audio($0.file).path) }.count; status=healthy && missing==0 ? "Database and audio-file presence checks passed.":"Collection needs attention: \(missing) missing audio files. Export a backup before making repairs." } catch { status=error.localizedDescription }
    }
}
private struct ExportPicker:UIViewControllerRepresentable {
    let url:URL
    func makeUIViewController(context:Context)->UIDocumentPickerViewController { UIDocumentPickerViewController(forExporting:[url],asCopy:true) }
    func updateUIViewController(_ controller:UIDocumentPickerViewController,context:Context) {}
}
