# Third-party software and services

Digital Analog application sources are provided under the MIT License; see LICENSE in the source repository. No source-code license grants rights in music or album images.

## Bundled or linked software

| Component | Version / origin | License |
| --- | --- | --- |
| SQLite | Operating-system library | Public domain; https://sqlite.org/copyright.html |
| Apple frameworks (SwiftUI, AVFoundation, MediaPlayer, ImageIO and others) | iOS SDK | Apple SDK terms |

The app has no other third-party code dependencies.

## Online metadata services

When the app looks up album details and cover art for a record in your library, it queries these services. No audio is sent or received.

- MusicBrainz web service for recording and release metadata: https://musicbrainz.org/doc/MusicBrainz_API (data under CC0 / CC BY-NC-SA as described by MetaBrainz).
- Cover Art Archive for front covers: https://coverartarchive.org/ . Cover Art Archive is an archive, not an image license; rights remain with the respective owners.

Retrieved artwork is stored in app-owned storage for offline use. Playback, playlists and browsing never require a network connection.
