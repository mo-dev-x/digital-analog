# Digital Analog — reference-led native design

The user's supplied ten-screen reference is the visual benchmark: restrained editorial serif headings, dense album galleries, near-black space, cinematic artwork, a floating pill player and a circular collection composition. Authentic artwork comes from the user's library; commercial recordings and album covers are not bundled in the app.

The listening room presents a contextual artwork hero, floating search, continue-listening sleeves and recently added tracks. Your Collection opens within the same canvas into a bounded, interactive album carousel and explicit song/album/artist/playlist perspectives. Albums use a compact adaptive cover grid. Opening a record or player retains the shared artwork geometry. Search looks only inside the user's library, with All/Songs/Albums/Artists/Playlists scopes, an artist view, and mood shortcuts that filter the offline library using explicitly saved genre tags. Unknown genres are never inferred as moods.

## Technology choices

- The collection keeps at most five album groups on screen, with stable identifiers, a prominent central sleeve, smaller neighbors and geometry-relative positions bounded by the available width. Horizontal drag or visible arrows change focus; tapping the center opens that album. Its lookup is cached and selection survives library updates.
- `matchedGeometryEffect`, gesture state and interruptible native springs preserve artwork continuity. Reduce Motion removes navigation translations, springs and crossfades.
- iOS 26 `GlassEffectContainer` groups related floating controls; `glassEffect(.regular.interactive())` supplies the actual system material and touch response for floating controls. Earlier versions use native Material; Reduce Transparency substitutes an opaque surface. Glass is restricted to controls, rather than placed over every content row.
- All artwork, including covers retrieved from Cover Art Archive, is stored in app-owned storage and loaded through an ImageIO cache, so offline covers never depend on a network cache.
- UIKit's UISlider supplies native accessibility and input behavior for the fine playback scrubber. Its thumb is rendered locally at the intended size; the interaction region remains 44 points.
- ImageIO downsamples local artwork. Core Graphics generates varied editorial fallback covers only after embedded and official cover resolution fail. Image composition is fitted rather than cropped; weighted hue sampling derives restrained ambient lighting without averaging rich covers into gray. SF Symbols and semantic system typography keep controls native and support Dynamic Type. There are no image-generation or animation service calls at runtime. Player artwork lighting is a persistent user preference; storage labels come from real local files.
- Xcode's simulator, hosted XCTest render attachments and xcresult exports provide actual UI captures. Render fixtures use synthetic audio and real cover crops from the user's supplied reference. They are low-resolution comparison assets, not commercial songs or proof of production metadata matching. The reference and fixtures belong only to the test bundle and do not ship inside the release application.

## Primary references

- Apple, Applying Liquid Glass to custom views: https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views
- Apple, Adopting Liquid Glass: https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
- Apple, Build a SwiftUI app with the new design: https://developer.apple.com/videos/play/wwdc2025/323/
- Apple, Compose custom layouts with SwiftUI: https://developer.apple.com/videos/play/wwdc2022/10056/
- Apple, Animate with springs: https://developer.apple.com/videos/play/wwdc2023/10158/

## Validation boundary

CI must compile every revision and run the hosted suite before the new build is delivered. Native screenshot attachments cover the listening room, collection, album browser, player, search, settings, queue and playlist detail. These establish what rendered in the test environment, not a measured animation frame rate. Small-screen (375 × 667) and large Dynamic Type layouts also have native render coverage. VoiceOver focus, interactive transitions, real iOS 26 optical appearance and sustained performance/battery behavior still require physical-device review and Instruments. No 120 Hz or Apple-quality performance claim is made without measurement.

## Artwork resolution and rights

Metadata assignment and artwork selection are separate. Ambiguous releases of the same confidently identified recording may still yield a genuine cover, while the app leaves uncertain album assignments for the user to correct. Different recordings, versions or artists remain excluded. Cover Art Archive is an archive, not a blanket image license; rights remain with the respective owners. Artwork is saved in app-owned storage for offline use. Settings → Advanced → Find missing album artwork repairs generated covers without overwriting a simultaneous metadata edit.

## Reference comparison, implemented corrections

| Screen | Correction and review target |
| --- | --- |
| Collection | Real sleeves inside subtle circular light enclosures; 170 pt focus, 78 pt neighbors, bounded five-item window, captions below, 44 pt navigation rows. Preserve full cover composition rather than clipping faces into circles. |
| Now Playing | Square cover limited to 36% of available height (310 pt cap), 64 pt central control, grouped transport controls, concentrated hue-derived glow, editorial title, small timestamps and integrated Lyrics/Queue strip. |
| Mini-player | 34 pt cover and compact pill; safe-area inset reserves content space. Shared artwork identity links it to the player. |
| Albums | Adaptive two/three-column cover grid, small functional labels and horizontal lens filters. |
| Album detail | Real hero sleeve, quiet lighting, play/shuffle and compact tracks; same album identifier drives expansion. |
| Search | Floating input, instant offline matching across songs, albums, artists and playlists, scope chips, compact result rows and contextual dismissal. |
| Playlist | Artwork hero, contrasting editorial title, compact track list, native reordering and persistent edits. |
| Queue | 46 pt cover rows, current indication, native reorder/delete and expandable player drawer. |
| Settings | Compact 46 pt surfaces, real-artwork atmosphere, actual persistent settings and storage. |
| Mood | Visible mood buttons map to explicit local genre filters. No decorative central vinyl simulation or unsupported audio-emotion inference. |

The first real-artwork render review identified edge-clipped outer collection covers and a diagnostic image leaking from another persistence test. The subsequent revision bounds outer positions to the width and resets only the test catalogue before seeding visual fixtures. Large text intentionally permits vertical player scrolling; smaller cover sizing keeps the transport visible at ordinary text sizes. Static captures cannot validate interruption quality or frame rate; those remain hardware checks.

Lyrics are user-imported plain text or timed LRC, stored with track metadata and available offline. The compact drawer supports editing and synchronized highlighting; no paid lyrics service or fictitious lyric content is introduced.
