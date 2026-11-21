# Apple acceptance procedure — native and physical gates pending

Portable results are recorded separately in Verification/RESULTS.md. Record device, iOS, Xcode, build identifier and observed results for these gates. A generated project or syntax parse does not establish native compilability.

## Build and runtime packaging

1. On a Mac with Xcode 26+, run generate_project.py.
2. Build the app target for simulator and physical device; fix all compiler/linker/runtime errors.
3. Run the deterministic hosted iOS tests, not merely the portable Swift package.
4. Run Release and inspect signing/provisioning, file protection and privacy manifests. Confirm the app bundle contains no embedded third-party frameworks.
5. Retain xcresult and logs. Hosted CI is disabled by default; only enable it after deliberately reviewing allowance and spending controls. An unsigned CI IPA must be re-signed before use.

## Complete journey

Use DRM-free audio files you own.

1. Open → Collection options → Import audio → select several files from Files.
2. Inspect network destinations: only MusicBrainz and Cover Art Archive lookups may occur, and only for metadata/artwork.
3. Confirm each audio file is present, readable and registered only after successful validation.
4. Confirm automatic artwork is saved. For an ambiguous album, choose the correct release in Edit record. Repeat with unavailable artwork providers and no embedded artwork: a persistent generated illustration must remain.
5. Enable airplane mode, relaunch, browse, play and seek.
6. Create a playlist, add/reorder/remove records, favorite a song, restart and confirm persistence.
7. Lock the phone for at least one hour. Test Control Center, lock-screen seek, headphones, Bluetooth/AirPlay output, disconnection and interruptions.
8. Search for songs, albums, artists and playlists in every scope, with airplane mode enabled, and confirm results open the correct album, artist view, playlist or song.
9. Test artwork provider outages: imports must still succeed with a generated cover.

## Recovery and integrity

- Interrupt during artwork lookup and final import. Relaunch; no partially imported track may appear in the collection.
- Test rapid repeated imports of the same file, storage-full, DRM-protected and corrupt audio, and artwork provider 403/404/429/503 responses.
- Remove the current queue item, delete its underlying library track, reorder while playing, exhaust shuffle, repeat one/all and restore a paused position.
- Export a backup to Files, restore it to a fresh install and verify hashes, playlist ordering and covers. Repeat import; duplicate audio/source identities must remain unique. An invalid backup must not partially mutate database records.
- Test upgrade from the earlier JSON catalog using a copy, including an interruption midway through migration. The new SQLite path must not destroy the original file on failure.
- Keep a backup before changing signing identity. Test SideStore/AltStore renewal and bundle-ID rewriting. Confirm refresh actually succeeds rather than relying on the enable switch.

## Design/accessibility/performance

- Inspect the record rail, album expansion, search overlay, row-to-player and compact-to-player transitions against the reference.
- Reverse gestures midway, change tracks rapidly and navigate during artwork loading. Essential controls need visible alternatives.
- Test VoiceOver, Reduce Motion, maximum Dynamic Type, Bold Text, contrast, RTL, small-screen safe areas and focus restoration.
- Benchmark 100/1,000/10,000 tracks with large covers. Use Instruments for main-thread work, hitches, memory and long background listening power consumption. No 120 Hz or scale claim is accepted without measurements.

The release gate remains open until native compilation, runtime packaging, the complete import/offline/locked journey, signing refresh and visual/performance checks pass on Apple hardware.

## Visual regression procedure

The hosted render test exports fourteen full-screen attachments plus the collection studies: ListeningRoom, Collection, Albums, NowPlaying, Search, NowPlaying-SE, NowPlaying-LargeType, AlbumDetail, SearchResults (local search), SearchArtists (artist scope), Lyrics, Settings, Queue and Playlist. Export attachments with the CI script and use manifest.json to resolve their readable names. Compare these against Tests/Fixtures/visual-reference.jpeg at equal normalized screen heights. Review complete bounds, including safe areas and player strip, rather than cropping out problem areas.

The reference image and its runtime cover crops are test-only; synthetic WAV files are deliberately not commercial recordings. Confirm the release IPA has no visual-reference.jpeg, tone.wav, reference-* fixture media or test bundle. Real user covers must come from permitted artwork sources, embedded metadata or user import.

On a physical phone, swipe the collection repeatedly, reverse midway, open a focused album, expand the mini-player and dismiss slowly/quickly. Confirm outer sleeves remain visible at narrow widths, vertical scrolling still works, and focus survives adding/deleting music. At large text sizes, scroll the player to reach secondary actions; labels must remain readable. Add a local genre tag and use a mood in search with airplane mode enabled. Import an LRC file, restart and confirm persistence and highlighting. Verify generated-cover recovery preserves manual artwork and concurrent title/artist edits.
