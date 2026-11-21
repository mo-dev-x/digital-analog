import AVFoundation
import MediaPlayer
import SwiftUI
import Combine
import DigitalAnalogCore

@MainActor final class Playback:ObservableObject {
    @Published private(set) var current:Track?
    @Published private(set) var playing=false
    @Published private(set) var buffering=false
    @Published private(set) var position:Double=0
    @Published private(set) var state=QueueState()
    var queue:[UUID] { state.ids }
    var shuffle:Bool { state.shuffle }
    var repeatMode:Int { state.repeatMode.rawValue }
    private let player=AVPlayer()
    private weak var library:Library?
    private var timeObserver:Any?
    private var playerObservation:NSKeyValueObservation?
    private var itemObservation:NSKeyValueObservation?
    private var tokens:[NSObjectProtocol]=[]
    private var libraryToken:AnyCancellable?
    private var saveTask:Task<Void,Never>?
    private var lastSave=Date.distantPast
    private var interrupted=false
    private var art:MPMediaItemArtwork?
    private var artTask:Task<Void,Never>?
    private var artKey:String?
    init(library:Library) {
        self.library=library
        do { try AVAudioSession.sharedInstance().setCategory(.playback,mode:.default) } catch { library.error=error.localizedDescription }
        playerObservation=player.observe(\.timeControlStatus,options:[.new]) { [weak self] player,_ in
            let value=player.timeControlStatus
            Task { @MainActor in guard let self else { return }; self.playing=value == .playing; self.buffering=value == .waitingToPlayAtSpecifiedRate; self.nowPlaying() }
        }
        timeObserver=player.addPeriodicTimeObserver(forInterval:CMTime(seconds:0.25,preferredTimescale:600),queue:.main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }; self.position=max(0,time.seconds.isFinite ? time.seconds : 0)
                if self.playing && Date().timeIntervalSince(self.lastSave)>10 { self.persist(); self.lastSave=Date() }
            }
        }
        libraryToken=library.$catalog.sink { [weak self] catalog in
            guard let self else { return }
            let old=self.current?.id
            self.state.reconcile(available:Set(catalog.tracks.map(\.id)))
            if let old,let updated=catalog.tracks.first(where: { $0.id==old }) { self.current=updated; self.updateArtwork(updated); self.nowPlaying() }
            else if old != nil {
                let continuePlayback=self.playing || self.buffering
                if let next=self.state.current,let track=catalog.tracks.first(where:{ $0.id==next }) { self.load(track); if continuePlayback { self.resume() } }
                else { self.position=0; self.pause(); self.current=nil; self.player.replaceCurrentItem(with:nil); self.art=nil; MPNowPlayingInfoCenter.default().nowPlayingInfo=nil }
            }
        }
        observe(.AVPlayerItemDidPlayToEndTime) { [weak self] note in guard let self,let item=note.object as? AVPlayerItem,item === self.player.currentItem else { return }; self.next(automatic:true) }
        observe(.AVPlayerItemFailedToPlayToEndTime) { [weak self] _ in self?.failed("This audio could not finish playing. Try importing the record again.") }
        observe(AVAudioSession.interruptionNotification) { [weak self] note in
            guard let self,let type=note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt else { return }
            if type==AVAudioSession.InterruptionType.began.rawValue { self.interrupted=self.playing || self.buffering; self.pause() }
            else { let options=AVAudioSession.InterruptionOptions(rawValue:note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0); if self.interrupted && options.contains(.shouldResume) { self.resume() }; self.interrupted=false }
        }
        observe(AVAudioSession.routeChangeNotification) { [weak self] note in if note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { self?.pause() } }
        observe(AVAudioSession.mediaServicesWereResetNotification) { [weak self] _ in
            guard let self else { return }; self.pause(); do { try AVAudioSession.sharedInstance().setCategory(.playback,mode:.default) } catch { self.library?.error=error.localizedDescription }; if let track=self.current { self.load(track,at:self.position) }
        }
        configureRemoteCommands()
    }
    private func observe(_ name:Notification.Name,_ action:@escaping @MainActor @Sendable (Notification)->Void) {
        tokens.append(NotificationCenter.default.addObserver(forName:name,object:nil,queue:.main) { note in Task { @MainActor in action(note) } })
    }
    func restore() async {
        guard let store=library?.store else { return }
        do { state=try await store.queue(); state.reconcile(available:Set(library?.catalog.tracks.map(\.id) ?? [])); if let id=state.current,let track=library?.catalog.tracks.first(where: { $0.id==id }) { load(track,at:state.position) } } catch { library?.error=error.localizedDescription }
    }
    func play(_ track:Track,within tracks:[Track]) {
        state.select(track.id,in:tracks.map(\.id)); load(track); resume(); markPlayed(track); persist()
    }
    private func markPlayed(_ track:Track) { var copy=track; copy.lastPlayed=Date(); library?.update(copy) }
    private func load(_ track:Track,at seconds:Double=0) {
        guard FileManager.default.fileExists(atPath:Disk.audio(track.file).path) else { failed("The audio file is missing. Import this record again."); return }
        current=track; position=max(0,min(seconds,track.duration)); let item=AVPlayerItem(url:Disk.audio(track.file))
        itemObservation=nil
        itemObservation=item.observe(\.status,options:[.new]) { [weak self] item,_ in
            let status=item.status; let error=item.error?.localizedDescription
            Task { @MainActor in if status == .failed { self?.failed(error ?? "This audio format could not be played.") } }
        }
        player.replaceCurrentItem(with:item)
        if position>0 { player.seek(to:CMTime(seconds:position,preferredTimescale:600)) }
        updateArtwork(track); nowPlaying()
    }
    private func updateArtwork(_ track:Track) {
        let key="\(track.id)|\(track.artwork ?? "")|\(track.title)"
        guard artKey != key else { return }; artKey=key; artTask?.cancel()
        artTask=Task {
            let image=await ArtworkCache.image(track); guard !Task.isCancelled,self.current?.id==track.id else { return }
            art=MPMediaItemArtwork(boundsSize:image.size) { _ in image }; nowPlaying()
        }
    }
    func resume() {
        guard current != nil,player.currentItem != nil else { return }
        do { try AVAudioSession.sharedInstance().setActive(true); player.play(); nowPlaying() } catch { failed(error.localizedDescription) }
    }
    func pause() { player.pause(); playing=false; buffering=false; persist(); nowPlaying() }
    func toggle() { playing || buffering ? pause() : resume() }
    func seek(_ seconds:Double) {
        guard let current else { return }; let value=max(0,min(seconds.isFinite ? seconds : 0,current.duration)); position=value; state.position=value
        player.seek(to:CMTime(seconds:value,preferredTimescale:600),toleranceBefore:.zero,toleranceAfter:.zero) { [weak self] _ in Task { @MainActor in self?.nowPlaying() } }; persist()
    }
    func previous() { state.position=position; if let id=state.previous() { playQueueItem(id) } }
    func next(automatic:Bool=false) {
        guard let id=state.next(automatic:automatic) else { pause(); return }; playQueueItem(id)
    }
    private func playQueueItem(_ id:UUID) {
        guard let track=library?.catalog.tracks.first(where: { $0.id==id }) else { return }; load(track); resume(); markPlayed(track); persist()
    }
    func playQueued(_ id:UUID) { guard state.ids.contains(id) else { return }; state.select(id); playQueueItem(id) }
    func setShuffle(_ value:Bool) { state.setShuffle(value); persist() }
    func cycleRepeat() { state.repeatMode=RepeatMode(rawValue:(state.repeatMode.rawValue+1)%3) ?? .off; persist() }
    func reorderQueue(_ order:[UUID]) { do { try state.reorder(order); persist() } catch { library?.error=error.localizedDescription } }
    func removeFromQueue(_ id:UUID) {
        let old=state.current; let continuePlayback=playing; state.remove(id)
        if old != state.current {
            if let next=state.current,let track=library?.catalog.tracks.first(where: { $0.id==next }) { load(track); if continuePlayback { resume() } }
            else { position=0; pause(); player.replaceCurrentItem(with:nil); current=nil; MPNowPlayingInfoCenter.default().nowPlayingInfo=nil }
        }; persist()
    }
    func persist() {
        state.position=position; let snapshot=state; guard let store=library?.store else { return }
        // Cancel only the waiting coalescing task; the actor commit itself is transactional.
        saveTask?.cancel(); saveTask=Task { do { try await Task.sleep(nanoseconds:150_000_000); try await store.saveQueue(snapshot) } catch is CancellationError {} catch { library?.error=error.localizedDescription } }
    }
    func flush() async { saveTask?.cancel(); guard let store=library?.store else { return }; state.position=position; do { try await store.saveQueue(state) } catch { library?.error=error.localizedDescription } }
    private func failed(_ message:String) { pause(); library?.error=message }
    private func configureRemoteCommands() {
        let r=MPRemoteCommandCenter.shared()
        r.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.resume() }; return .success }
        r.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        r.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.toggle() }; return .success }
        r.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.next() }; return .success }
        r.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.previous() }; return .success }
        r.changePlaybackPositionCommand.addTarget { [weak self] event in guard let event=event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }; let seconds=event.positionTime; Task { @MainActor in self?.seek(seconds) }; return .success }
    }
    private func nowPlaying() {
        guard let t=current else { return }
        var info:[String:Any]=[MPMediaItemPropertyTitle:t.title,MPMediaItemPropertyArtist:t.artist,MPMediaItemPropertyAlbumTitle:t.album,MPMediaItemPropertyPlaybackDuration:t.duration,MPNowPlayingInfoPropertyElapsedPlaybackTime:position,MPNowPlayingInfoPropertyPlaybackRate:playing ? 1.0 : 0.0]
        if let art { info[MPMediaItemPropertyArtwork]=art }; MPNowPlayingInfoCenter.default().nowPlayingInfo=info
    }
}
