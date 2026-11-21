import Foundation
public enum MetadataResponse {
    public static func candidates(from data: Data) throws -> [MetadataCandidate] {
        struct Response: Decodable { var recordings: [Item] }
        struct Credit: Decodable { var name: String?; var artist: Artist?; struct Artist:Decodable { var name:String } }
        struct Release:Decodable { var id:String; var title:String; var date:String?; var status:String? }
        struct Item:Decodable {
            var id:String; var title:String; var length:Double?; var credit:[Credit]; var releases:[Release]?
            enum CodingKeys:String,CodingKey { case id,title,length,releases; case credit="artist-credit" }
        }
        return try JSONDecoder().decode(Response.self,from:data).recordings.flatMap { item in
            let artist=item.credit.compactMap { $0.name ?? $0.artist?.name }.joined(separator:" & ")
            let releases=(item.releases ?? []).filter { $0.status == nil || $0.status == "Official" }
            if releases.isEmpty { return [MetadataCandidate(recordingID:item.id,title:item.title,artist:artist,duration:item.length.map { $0/1000 })] }
            return releases.map { release in MetadataCandidate(recordingID:item.id,title:item.title,artist:artist,duration:item.length.map { $0/1000 },releaseID:release.id,album:release.title,year:release.date.flatMap { Int($0.prefix(4)) }) }
        }
    }
}
public enum RetryPolicy {
    public static func retryable(status: Int) -> Bool { [408,429,500,502,503,504].contains(status) }
    public static func delay(attempt: Int, retryAfter: String? = nil, now: Date = Date()) -> Double {
        if let retryAfter, let seconds=Double(retryAfter) { return min(120,max(0,seconds)) }
        if let retryAfter {
            let f=DateFormatter(); f.locale=Locale(identifier:"en_US_POSIX"); f.timeZone=TimeZone(secondsFromGMT:0); f.dateFormat="EEE, dd MMM yyyy HH:mm:ss zzz"
            if let date=f.date(from:retryAfter) { return min(120,max(0,date.timeIntervalSince(now))) }
        }
        return min(30,pow(2,Double(max(0,min(attempt,5)))))
    }
}
