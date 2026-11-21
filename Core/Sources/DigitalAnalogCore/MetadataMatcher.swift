import Foundation
public struct MetadataCandidate: Codable, Equatable, Sendable {
    public var recordingID: String
    public var title: String
    public var artist: String
    public var duration: Double?
    public var releaseID: String?
    public var album: String?
    public var year: Int?
    public init(recordingID: String, title: String, artist: String, duration: Double? = nil, releaseID: String? = nil, album: String? = nil, year: Int? = nil) { self.recordingID=recordingID; self.title=title; self.artist=artist; self.duration=duration; self.releaseID=releaseID; self.album=album; self.year=year }
}
public enum MetadataMatcher {
    public static func normalized(_ text: String) -> String {
        text.folding(options:[.diacriticInsensitive,.caseInsensitive],locale:Locale(identifier:"en_US_POSIX")).components(separatedBy:CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator:" ")
    }
    public static func qualifiers(_ title: String) -> Set<String> {
        let words=Set(normalized(title).split(separator:" ").map(String.init))
        return words.intersection(["live","remix","cover","instrumental","acoustic","remastered","remaster","sped","slowed","karaoke"])
    }
    public static func cleanTitle(_ title: String) -> String {
        var s=title
        for pattern in [#"(?i)\s*[\[(](official\s+(music\s+)?(video|audio)|lyrics?|hd|hq|4k)[\])]"#, #"(?i)\s*\|\s*official.*$"#] {
            s=s.replacingOccurrences(of:pattern,with:"",options:.regularExpression)
        }
        return s.trimmingCharacters(in:.whitespacesAndNewlines)
    }
    private static func similarity(_ a: String,_ b: String) -> Double {
        let x=Set(normalized(a).split(separator:" ")); let y=Set(normalized(b).split(separator:" "))
        guard !x.isEmpty && !y.isEmpty else { return 0 }; return Double(x.intersection(y).count)/Double(x.union(y).count)
    }
    public static func score(_ source: Recording,_ candidate: MetadataCandidate) -> Double {
        guard qualifiers(source.title)==qualifiers(candidate.title) else { return 0 }
        let title=similarity(cleanTitle(source.title),candidate.title)
        let artist=similarity(source.artist,candidate.artist)
        var duration=0.5
        if let a=source.duration, let b=candidate.duration { if abs(a-b)>12 { return 0 }; duration=max(0,1-abs(a-b)/12) }
        return title*0.55+artist*0.35+duration*0.1
    }
    public static func confident(_ source: Recording, candidates: [MetadataCandidate]) -> MetadataCandidate? {
        // A recording can have many releases. Never auto-select an ambiguous release.
        let ranked=candidates.map { ($0,score(source,$0)) }.sorted { $0.1>$1.1 }
        guard let first=ranked.first, first.1>=0.9 else { return nil }
        if ranked.count>1, first.1-ranked[1].1<0.06 { return nil }
        return first.0
    }
}
