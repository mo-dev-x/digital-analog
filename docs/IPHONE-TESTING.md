# Test the public edition on an iPhone

## Which build

No build of the public local-library edition exists yet. Build it on a Mac with Xcode (see the README), or wait for a deliberately enabled CI run that produces `DigitalAnalog-unsigned.ipa`. Earlier private builds are a different app and must not be used to evaluate this edition. An unsigned IPA needs signing before it can install; see INSTALL.md. Never send Apple Account credentials in chat.

The app is version 0.2.0 (2), bundle ID `personal.digitalanalog.player`, minimum iOS 17.

## Short first session

1. Sign and install. Open Digital Analog. A normal Release install starts with an empty personal collection; screenshot albums are test fixtures, not included music.
2. Import a DRM-free audio file you own through **Collection options → Import audio**. Confirm title, measured duration and artwork. If matching fails, open Record details, use **Find album & artwork**, or correct the metadata and artwork manually. Play, seek, pause and resume.
3. Import a few more records from different artists and albums. Open search and look up a song title, an album, an artist and a playlist name. Check each scope (All, Songs, Albums, Artists, Playlists), open an artist and an album from the results, and confirm playback starts from a song result.
4. Turn on Airplane Mode and separately disable Wi-Fi. Close and reopen Digital Analog. Confirm audio, covers, search and the collection still work.
5. Create a playlist, add the track, favorite it, reorder the queue and restart. Verify these changes persist.
6. Play a local track, lock the iPhone for five minutes, then use lock-screen pause/play and seek. Test headphones if available. This first check does not replace the longer QA session.
7. Unlock and confirm playback time and current track agree. Export a collection backup before reinstalling or changing signing identity.

## Recovery and interaction session

- Import the same file twice and confirm the collection keeps one entry. Import a corrupt or DRM-protected file and confirm it is rejected without changing the collection.
- Drag between collection albums slowly, reverse direction midway, select a focused album, and open the player. Try a short downward drag that should snap back and a longer drag that dismisses. Ensure playback controls remain responsive.
- Enable iOS Reduce Motion, then larger text and VoiceOver separately. Check that visible navigation alternatives, search results and playback controls remain usable.
- Refresh the signature before expiry and confirm the same collection survives. Do not delete the app to fix signing unless a verified backup exists.

## Useful feedback

Send the build version, iPhone/iOS version, exact action, expected result, actual result and a short screen recording or screenshot. Separate visual feedback from playback, import or artwork-matching failures. Device performance and background behavior remain unverified until tested on hardware.
