import Foundation
public enum LibraryMood:String,CaseIterable,Sendable {
    case chill="Chill",sad="Sad",workout="Workout",love="Love",focus="Focus",party="Party"
    private var genres:[String] {
        switch self { case .chill:return ["jazz","soul","ambient","downtempo","lounge"];case .sad:return ["blues","soul","ballad"];case .workout:return ["hip hop","hiphop","rap","rock","electronic"];case .love:return ["soul","r b","rnb","r and b","ballad"];case .focus:return ["instrumental","jazz","classical","ambient"];case .party:return ["dance","pop","disco","house","funk"] }
    }
    /// A transparent genre lens, not an invented emotional analysis of audio.
    public func matches(_ track:Track)->Bool {
        guard let genre=track.genre,!genre.isEmpty else { return false }
        let value=MetadataMatcher.normalized(genre)
        return genres.contains { value.contains($0) }
    }
}
