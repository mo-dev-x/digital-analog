import Foundation
import UIKit
import ImageIO
import DigitalAnalogCore

struct ArtworkResolution:Sendable {
    var file:String?
    var match:MetadataCandidate?
    var provenance:String
}
actor ArtworkService {
    static let shared=ArtworkService()
    private var nextRequest=Date.distantPast
    private var metadataCache:[String:[MetadataCandidate]]=[:]
    private let session:URLSession = {
        let c=URLSessionConfiguration.ephemeral; c.timeoutIntervalForRequest=20; c.timeoutIntervalForResource=40; c.urlCache=nil
        return URLSession(configuration:c)
    }()
    private func fetch(_ url:URL,maxBytes:Int=2_000_000) async throws -> Data {
        let attempts=url.host=="musicbrainz.org" ? 5:3
        for attempt in 0..<attempts {
            try Task.checkCancellation()
            var request=URLRequest(url:url); request.setValue("DigitalAnalog/0.2 (https://github.com/mo-dev-x/digital-analog)",forHTTPHeaderField:"User-Agent")
            let (bytes,response)=try await session.bytes(for:request)
            guard let response=response as? HTTPURLResponse else { throw AppFailure.message("Invalid artwork response") }
            if RetryPolicy.retryable(status:response.statusCode),attempt<attempts-1 {
                let wait=RetryPolicy.delay(attempt:attempt,retryAfter:response.value(forHTTPHeaderField:"Retry-After"))
                try await Task.sleep(nanoseconds:UInt64(wait*1_000_000_000)); continue
            }
            guard (200...299).contains(response.statusCode) else { throw AppFailure.message("Artwork provider returned \(response.statusCode)") }
            if response.expectedContentLength>Int64(maxBytes) { throw AppFailure.message("Artwork exceeds the image size limit") }
            var data=Data(); data.reserveCapacity(min(maxBytes,512_000))
            for try await byte in bytes { data.append(byte); if data.count>maxBytes { throw AppFailure.message("Artwork exceeds the image size limit") } }
            return data
        }
        throw AppFailure.message("Artwork provider unavailable")
    }
    func candidates(_ recording:Recording) async throws -> [MetadataCandidate] {
        let key=MetadataMatcher.normalized(recording.artist)+"|"+MetadataMatcher.normalized(recording.title)+"|"+MetadataMatcher.normalized(recording.album ?? "")
        if let cached=metadataCache[key] { return cached }
        // Cancelled searches do not reserve a long chain of future rate slots.
        while nextRequest>Date() { try await Task.sleep(nanoseconds:UInt64(max(0,nextRequest.timeIntervalSinceNow)*1_000_000_000)) }
        try Task.checkCancellation(); nextRequest=Date().addingTimeInterval(1.1)
        if let cached=metadataCache[key] { return cached }
        var url=URLComponents(string:"https://musicbrainz.org/ws/2/recording/")!
        let title=MetadataMatcher.normalized(MetadataMatcher.cleanTitle(recording.title)); let artist=MetadataMatcher.normalized(recording.artist)
        let albumFilter=recording.album.flatMap { $0 == "Singles" ? nil:MetadataMatcher.normalized($0) }.map { " AND release:\"\($0)\"" } ?? ""
        url.queryItems=[URLQueryItem(name:"query",value:"recording:\"\(title)\" AND artist:\"\(artist)\""+albumFilter),URLQueryItem(name:"fmt",value:"json"),URLQueryItem(name:"limit",value:"25")]
        let values=try MetadataResponse.candidates(from:await fetch(url.url!))
        if metadataCache.count>=128 { metadataCache.removeAll(keepingCapacity:true) }
        metadataCache[key]=values; return values
    }
    func resolve(_ recording:Recording,key:String) async -> ArtworkResolution {
        let values = !Task.isCancelled ? (try? await candidates(recording)) ?? []:[]
        let match=MetadataMatcher.confident(recording,candidates:values)
        for candidate in MetadataMatcher.artworkCandidates(recording,candidates:values).prefix(4) {
            guard !Task.isCancelled else { break }
            if let release=candidate.releaseID,let url=URL(string:"https://coverartarchive.org/release/\(release)/front-500"),let data=try? await fetch(url,maxBytes:12_000_000),let name=try? await ArtworkFiles.store(data,key:key) {
                return ArtworkResolution(file:name,match:match,provenance:url.absoluteString)
            }
        }
        return ArtworkResolution(file:nil,match:match,provenance:"Generated on this iPhone")
    }
    func cover(for candidate:MetadataCandidate,key:String) async throws -> String? {
        guard let release=candidate.releaseID,let url=URL(string:"https://coverartarchive.org/release/\(release)/front-500") else { return nil }
        let bytes=try await fetch(url,maxBytes:12_000_000)
        return try await ArtworkFiles.store(bytes,key:key)
    }
}
private extension Array where Element==MetadataCandidate {
    func withConfidentMatch(_ recording:Recording) -> MetadataCandidate? { MetadataMatcher.confident(recording,candidates:self) }
}
enum ArtworkFiles {
    static func store(_ bytes:Data,key:String) async throws -> String {
        try await Task.detached(priority:.utility) {
            guard let source=CGImageSourceCreateWithData(bytes as CFData,nil),let cg=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:1200,kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary),let data=UIImage(cgImage:cg).jpegData(compressionQuality:0.88) else { throw AppFailure.message("The selected artwork is not a readable image") }
            let name=key+".jpg"; try data.write(to:Disk.art(name),options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication]); return name
        }.value
    }
    @MainActor static func generated(_ track:Track) async throws -> String {
        guard let data=ArtworkCache.fallback(track).jpegData(compressionQuality:0.9) else { throw AppFailure.message("Cannot generate artwork") }
        let name=track.id.uuidString+".jpg"; try data.write(to:Disk.art(name),options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication]); return name
    }
}
