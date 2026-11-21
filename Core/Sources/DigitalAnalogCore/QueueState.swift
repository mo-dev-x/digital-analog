import Foundation
public enum RepeatMode: Int, Codable, Sendable { case off, all, one }
public struct QueueState: Codable, Equatable, Sendable {
    public var ids: [UUID]
    public var current: UUID?
    public var position: Double
    public var shuffle: Bool
    public var repeatMode: RepeatMode
    public private(set) var history: [UUID]
    public private(set) var remaining: [UUID]
    public init(ids: [UUID] = [], current: UUID? = nil, position: Double = 0, shuffle: Bool = false, repeatMode: RepeatMode = .off) {
        self.ids=Self.unique(ids); self.current=current; self.position=max(0,position.isFinite ? position : 0); self.shuffle=shuffle; self.repeatMode=repeatMode; history=[]; remaining=Self.unique(ids).filter { $0 != current }
    }
    private static func unique(_ ids: [UUID]) -> [UUID] { var seen=Set<UUID>(); return ids.filter { seen.insert($0).inserted } }
    public mutating func select(_ id: UUID, in values: [UUID]? = nil) {
        if let values { ids=Self.unique(values) }
        if !ids.contains(id) { ids.append(id) }
        current=id; position=0; history=[]; remaining=ids.filter { $0 != id }
    }
    public mutating func setShuffle(_ enabled: Bool) { shuffle=enabled; remaining=ids.filter { $0 != current }; history=[] }
    public mutating func next(automatic: Bool = false, choose: (Int) -> Int = { Int.random(in: 0..<$0) }) -> UUID? {
        guard !ids.isEmpty else { current=nil; position=0; return nil }
        if automatic && repeatMode == .one, let current { position=0; return current }
        if shuffle {
            remaining=remaining.filter { ids.contains($0) && $0 != current }
            if remaining.isEmpty {
                guard repeatMode == .all || !automatic else { return nil }
                remaining=ids.filter { $0 != current }
            }
            if remaining.isEmpty { position=0; return current ?? ids.first }
            let index=max(0,min(choose(remaining.count),remaining.count-1)); let next=remaining.remove(at: index)
            if let current { history.append(current) }; current=next; position=0; return next
        }
        let index=current.flatMap { ids.firstIndex(of:$0) } ?? -1
        if index+1 >= ids.count && automatic && repeatMode != .all { return nil }
        let next=ids[(index+1)%ids.count]; if let current { history.append(current) }; current=next; position=0; return next
    }
    public mutating func previous() -> UUID? {
        if position > 3 { position=0; return current }
        if shuffle, let previous=history.popLast() {
            if let current, !remaining.contains(current) { remaining.append(current) }; current=previous; remaining.removeAll { $0 == previous }; position=0; return previous
        }
        guard !ids.isEmpty else { current=nil; return nil }
        let index=current.flatMap { ids.firstIndex(of:$0) } ?? 0
        current=ids[(index-1+ids.count)%ids.count]; position=0; return current
    }
    public mutating func remove(_ id: UUID) {
        let index=ids.firstIndex(of:id) ?? 0; ids.removeAll { $0 == id }; remaining.removeAll { $0 == id }; history.removeAll { $0 == id }
        if current == id { current=ids.isEmpty ? nil : ids[min(index,ids.count-1)]; position=0 }
    }
    public mutating func reorder(_ order: [UUID]) throws { guard order.count==ids.count, Set(order)==Set(ids) else { throw LibraryError.invalidOrder }; ids=order }
    public mutating func reconcile(available: Set<UUID>) { for id in ids where !available.contains(id) { remove(id) }; if let current, !available.contains(current) { self.current=nil; position=0 } }
}
