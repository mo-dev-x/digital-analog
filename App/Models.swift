import Foundation
import DigitalAnalogCore

enum Disk {
    static let root: URL = {
        let url=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("DigitalAnalog",isDirectory:true)
        for folder in ["Audio","Artwork","Exports"] { try? FileManager.default.createDirectory(at:url.appendingPathComponent(folder),withIntermediateDirectories:true,attributes:[.protectionKey:FileProtectionType.completeUntilFirstUserAuthentication]) }
        return url
    }()
    static func audio(_ name:String)->URL { root.appendingPathComponent("Audio").appendingPathComponent(name) }
    static func art(_ name:String)->URL { root.appendingPathComponent("Artwork").appendingPathComponent(name) }
}
struct Catalog {
    var tracks:[Track]=[]
    var playlists:[Playlist]=[]
}
enum AppFailure:Error,LocalizedError {
    case message(String)
    var errorDescription:String? { if case .message(let s)=self { return s }; return nil }
}
