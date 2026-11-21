import Foundation
public struct LyricLine:Identifiable,Equatable,Sendable {
    public var id:Int; public var time:Double?; public var text:String
}
public struct LyricsDocument:Sendable {
    public let lines:[LyricLine]
    public var synchronized:Bool { lines.contains { $0.time != nil } }
    public init(_ text:String) {
        let tag=try! NSRegularExpression(pattern:#"\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]"#)
        let offsetPattern=try! NSRegularExpression(pattern:#"\[offset:([+-]?\d+)\]"#,options:.caseInsensitive)
        let full=text as NSString
        let offset=offsetPattern.firstMatch(in:text,range:NSRange(location:0,length:full.length)).flatMap { Double(full.substring(with:$0.range(at:1))) }.map { $0/1000 } ?? 0
        var result:[LyricLine]=[]
        for raw in text.components(separatedBy:.newlines) {
            let source=raw as NSString; let matches=tag.matches(in:raw,range:NSRange(location:0,length:source.length))
            if matches.isEmpty {
                let plain=raw.trimmingCharacters(in:.whitespacesAndNewlines)
                if !plain.isEmpty,!plain.hasPrefix("[") { result.append(LyricLine(id:result.count,time:nil,text:plain)) }
            } else {
                let words=tag.stringByReplacingMatches(in:raw,range:NSRange(location:0,length:source.length),withTemplate:"").trimmingCharacters(in:.whitespacesAndNewlines)
                for match in matches {
                    let minutes=Double(source.substring(with:match.range(at:1))) ?? 0
                    let seconds=Double(source.substring(with:match.range(at:2))) ?? 0
                    guard seconds<60 else { continue }
                    let fraction=match.range(at:3).location==NSNotFound ? 0:(Double("0."+source.substring(with:match.range(at:3))) ?? 0)
                    result.append(LyricLine(id:result.count,time:max(0,minutes*60+seconds+fraction+offset),text:words))
                }
            }
        }
        let timed=result.filter { $0.time != nil }
        self.lines=timed.isEmpty ? result:timed.sorted { ($0.time!,$0.id)<($1.time!,$1.id) }
    }
    public func activeID(at seconds:Double)->Int? { lines.last { ($0.time ?? .infinity)<=seconds }?.id }
}
