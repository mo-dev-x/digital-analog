import SwiftUI

@MainActor final class Services:ObservableObject {
    let library:Library
    let playback:Playback
    init() { let library=Library(); self.library=library; playback=Playback(library:library) }
    private var started=false
    func start() async { guard !started else { return }; started=true; await library.start(); await playback.restore() }
}
@main struct DigitalAnalogApp:App {
    @StateObject private var services=Services()
    var body:some Scene {
        WindowGroup {
            Canvas(initialPerspective:ProcessInfo.processInfo.arguments.contains("--ui-fixtures") ? "Collection":"Room").environmentObject(services).environmentObject(services.library).environmentObject(services.playback)
                .task { await services.start()
#if DEBUG
                    do { try await InteractionFixtures.seed(services) } catch { services.library.error=error.localizedDescription }
#endif
                }
        }
    }
}
