import Foundation

public extension MetadataMatcher {
    /// Cover selection may try official releases of the same strongly identified
    /// recording without assigning an ambiguous release to the user's library.
    static func artworkCandidates(_ source:Recording,candidates:[MetadataCandidate])->[MetadataCandidate] {
        var ranked=candidates.filter { $0.releaseID != nil && score(source,$0)>=0.90 }
            .sorted { a,b in
                if let album=source.album {
                    let x=normalized(a.album ?? "")==normalized(album),y=normalized(b.album ?? "")==normalized(album)
                    if x != y { return x }
                }
                let x=score(source,a),y=score(source,b)
                if x != y { return x>y }
                return (a.year ?? Int.max)<(b.year ?? Int.max)
            }
        let album=source.album.map(normalized)
        let exactAlbum=album.map { name in ranked.contains { normalized($0.album ?? "")==name } } ?? false
        if exactAlbum { ranked=ranked.filter { normalized($0.album ?? "")==album } }
        guard let first=ranked.first else { return [] }
        // Ties between different recordings remain ambiguous. Multiple releases
        // of the same recording do not prevent obtaining its authentic cover.
        if !exactAlbum,ranked.contains(where: { $0.recordingID != first.recordingID && score(source,first)-score(source,$0)<0.06 }) { return [] }
        var seen=Set<String>()
        return ranked.filter { (exactAlbum || $0.recordingID==first.recordingID) && seen.insert($0.releaseID!).inserted }
    }
}
public struct ArtworkRGB:Equatable,Sendable {
    public var red:Double; public var green:Double; public var blue:Double
    public init(_ red:Double,_ green:Double,_ blue:Double) { self.red=red;self.green=green;self.blue=blue }
}
public enum ArtworkPalette {
    /// Weighted hue histogram rejects black borders, white type and gray shadows.
    /// A whole-image average tends to erase the red in dark photographic covers.
    public static func dominant(_ pixels:[ArtworkRGB])->ArtworkRGB {
        var buckets=Array(repeating:(weight:0.0,r:0.0,g:0.0,b:0.0),count:24)
        for p in pixels {
            let hi=max(p.red,p.green,p.blue),lo=min(p.red,p.green,p.blue),delta=hi-lo
            guard hi>0.14,delta/max(hi,0.001)>0.20 else { continue }
            let hue:Double
            if hi==p.red { hue=((p.green-p.blue)/delta).truncatingRemainder(dividingBy:6) }
            else if hi==p.green { hue=(p.blue-p.red)/delta+2 }
            else { hue=(p.red-p.green)/delta+4 }
            let index=Int(((hue/6+1).truncatingRemainder(dividingBy:1))*24)%24
            let weight=(delta/hi)*sqrt(hi)
            buckets[index].weight += weight; buckets[index].r += p.red*weight
            buckets[index].g += p.green*weight; buckets[index].b += p.blue*weight
        }
        guard let best=buckets.max(by:{$0.weight<$1.weight}),best.weight>0 else { return ArtworkRGB(0.28,0.26,0.23) }
        return ArtworkRGB(best.r/best.weight,best.g/best.weight,best.b/best.weight)
    }
}
public struct AlbumFocus:Equatable,Sendable {
    public private(set) var ids:[String]
    public private(set) var selected:String?
    public init(ids:[String],selected:String?=nil) {
        var seen=Set<String>(); let unique=ids.filter { seen.insert($0).inserted }; self.ids=unique
        self.selected=selected.flatMap { unique.contains($0) ? $0:nil } ?? unique.first
    }
    public mutating func select(_ id:String) { if ids.contains(id) { selected=id } }
    public mutating func advance(_ steps:Int) {
        guard !ids.isEmpty else { selected=nil; return }
        let index=selected.flatMap { ids.firstIndex(of:$0) } ?? 0
        selected=ids[((index+steps)%ids.count+ids.count)%ids.count]
    }
    public mutating func reconcile(_ values:[String]) { self=AlbumFocus(ids:values,selected:selected) }
    /// Only this bounded window is rendered, even for thousands of albums.
    public func window(radius:Int=2)->[String] {
        guard !ids.isEmpty else { return [] }
        let index=selected.flatMap { ids.firstIndex(of:$0) } ?? 0
        var seen=Set<String>()
        let offsets=[0]+(0..<min(max(0,radius),ids.count)).flatMap { [-($0+1),$0+1] }
        return offsets.compactMap { offset in
            let id=ids[((index+offset)%ids.count+ids.count)%ids.count]
            return seen.insert(id).inserted ? id:nil
        }
    }
}
