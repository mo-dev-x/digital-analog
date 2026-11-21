import SwiftUI
import DigitalAnalogCore
import UIKit
import ImageIO

@MainActor
enum ArtworkCache {
    private static var palettes: [String: Color] = [:]
    static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>(); c.totalCostLimit = 40 * 1024 * 1024; return c
    }()
    static func color(_ track: Track) -> Color {
        if let name = track.artwork, let color = palettes[name] { return color }
        let seed = track.digest.utf8.reduce(0) { ($0 &* 31 &+ Int($1)) & 0xFFFF }
        return Color(hue: Double(seed % 360) / 360, saturation: 0.4, brightness: 0.48)
    }
    static func fallback(_ track: Track) -> UIImage {
        let key = "fallback-\(track.id)-\(track.title)-\(track.artist)" as NSString
        if let image = cache.object(forKey: key) { return image }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 600), format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
        let image = renderer.image { context in
            UIColor(white: 0.045, alpha: 1).setFill(); context.fill(CGRect(x: 0, y: 0, width: 600, height: 600))
            let tint = UIColor(color(track))
            let cg=context.cgContext
            let seed=track.digest.utf8.reduce(0) { ($0 &* 31 &+ Int($1)) & 0xFFFF }
            switch seed%3 {
            case 0:
                tint.withAlphaComponent(0.7).setFill(); cg.fill(CGRect(x:280,y:0,width:320,height:600))
                UIColor(white:0.92,alpha:1).setFill(); cg.fill(CGRect(x:44,y:70,width:210,height:12))
                cg.saveGState(); cg.translateBy(x:320,y:240); cg.rotate(by:-0.25)
                UIColor.black.withAlphaComponent(0.35).setFill(); cg.fill(CGRect(x:-120,y:-150,width:170,height:410)); cg.restoreGState()
            case 1:
                for i in 0..<8 {
                    let x=CGFloat(i)*85-60
                    tint.withAlphaComponent(0.12+Double(i)*0.07).setFill()
                    let path=UIBezierPath(); path.move(to:CGPoint(x:x,y:0)); path.addLine(to:CGPoint(x:x+70,y:0));path.addLine(to:CGPoint(x:x-150,y:600));path.addLine(to:CGPoint(x:x-220,y:600));path.close();path.fill()
                }
            default:
                tint.withAlphaComponent(0.8).setFill(); cg.fill(CGRect(x:0,y:120,width:600,height:210))
                UIColor(white:0.9,alpha:1).setFill(); cg.fill(CGRect(x:50,y:75,width:80,height:80))
                UIColor.black.withAlphaComponent(0.3).setFill(); cg.fill(CGRect(x:210,y:210,width:340,height:200))
            }
            let style = NSMutableParagraphStyle(); style.lineBreakMode = .byTruncatingTail
            (track.title as NSString).draw(in: CGRect(x: 38, y: 454, width: 524, height: 80), withAttributes: [.font: UIFont(name:"Georgia",size:32) ?? UIFont.systemFont(ofSize:32), .foregroundColor: UIColor(white: 0.96, alpha: 1), .paragraphStyle: style])
            (track.artist.uppercased() as NSString).draw(in: CGRect(x: 40, y: 548, width: 520, height: 26), withAttributes: [.font: UIFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: UIColor(white: 0.65, alpha: 1), .kern: 3, .paragraphStyle: style])
        }
        cache.setObject(image, forKey: key, cost: 600 * 600 * 4); return image
    }
    static func image(_ track: Track) async -> UIImage {
        guard let name = track.artwork else { return fallback(track) }
        if let image = cache.object(forKey: name as NSString) { return image }
        let url = Disk.art(name)
        let loaded = await Task.detached(priority: .utility) { () -> UIImage? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 900, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
            return UIImage(cgImage: cg)
        }.value
        guard let loaded else { return fallback(track) }
        cache.setObject(loaded, forKey: name as NSString, cost: Int(loaded.size.width * loaded.size.height * 4))
        if let cg=loaded.cgImage {
            var bytes=[UInt8](repeating:0,count:16*16*4)
            bytes.withUnsafeMutableBytes { buffer in
                if let context=CGContext(data:buffer.baseAddress,width:16,height:16,bitsPerComponent:8,bytesPerRow:64,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) {
                    context.interpolationQuality = .medium; context.draw(cg,in:CGRect(x:0,y:0,width:16,height:16))
                }
            }
            let pixels=stride(from:0,to:bytes.count,by:4).map { ArtworkRGB(Double(bytes[$0])/255,Double(bytes[$0+1])/255,Double(bytes[$0+2])/255) }
            let rgb=ArtworkPalette.dominant(pixels)
            let tint=UIColor(red:CGFloat(rgb.red),green:CGFloat(rgb.green),blue:CGFloat(rgb.blue),alpha:1)
            var hue:CGFloat=0,saturation:CGFloat=0,brightness:CGFloat=0,alpha:CGFloat=0
            tint.getHue(&hue,saturation:&saturation,brightness:&brightness,alpha:&alpha)
            palettes[name]=Color(hue:Double(hue),saturation:Double(min(saturation,0.8)),brightness:Double(min(max(brightness,0.32),0.60)))
        }
        return loaded
    }
}
@MainActor
struct Cover: View {
    let track: Track
    var radius: CGFloat = 12
    @State private var image: UIImage?
    @State private var imageKey = "fallback"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    init(track:Track,radius:CGFloat=12) {
        self.track=track;self.radius=radius
        _image=State(initialValue:track.artwork.flatMap { ArtworkCache.cache.object(forKey:$0 as NSString) })
        _imageKey=State(initialValue:"\(track.id)|\(track.artwork ?? "")")
    }
    var body: some View {
        ZStack {
            DA.surface
            Image(uiImage: image ?? ArtworkCache.fallback(track)).resizable().scaledToFit().id(imageKey).transition(.opacity)
        }
        .aspectRatio(1, contentMode: .fit).clipped().clipShape(RoundedRectangle(cornerRadius: radius))
        .task(id: "\(track.id)-\(track.artwork ?? "")-\(track.title)-\(track.artist)") {
            let loaded=await ArtworkCache.image(track)
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration:0.3)) { image=loaded; imageKey="\(track.id)|\(track.artwork ?? "")" }
        }
        .accessibilityLabel("Artwork for \(track.title)")
    }
}
