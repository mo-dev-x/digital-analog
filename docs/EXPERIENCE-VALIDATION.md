# Experience validation

Design, functionality, and performance have independent acceptance gates. Passing unit tests does not establish visual quality, correct artwork matching, or hardware smoothness.

## Collection

The source includes orbital, fan, and sleeve-rail studies. The orbital architecture uses drag-driven position, scale, and depth with a bounded window of albums. Covers are circular only in the spatial collection; album detail, grids, and the player retain the square artwork. Verify focus identity, reversible gestures, neighbor legibility, vertical scrolling, visible navigation alternatives, and large-library behavior.

## Player and transitions

Check artwork continuity from collection or mini-player into Now Playing, interactive dismissal, short-drag snapback, reversal during motion, artwork changes, and Reduce Motion. Review the full composition: safe areas, editorial title, artist, progress, restrained controls, lighting, and queue/lyrics drawer.

The earlier timeline problem came from a one-second synthetic fixture. Current interaction fixtures construct valid 200-second WAV audio; production durations come from the imported asset.

## Existing evidence

No native evidence has been recorded for the public local-library edition yet. The UI journey in UITests/ covers synthesized taps, collection drags, slider seeking, player snapback/dismissal, queue, local search, playlist editing, settings, and relaunch, and records a simulator video when run. That is stronger evidence than state-driven animation alone, but is neither a human test nor a physical-device performance measurement.

A separate provider test retrieves covers for four diverse recording identities. Supplied identities and synthetic audio do not demonstrate general song recognition.

## Visual work still requiring native review

Earlier captures exposed low-resolution test-reference crops, an overly large album-detail hero, unused space below the player drawer, and a heavy selected playlist row. The branch includes a playlist styling correction, and the new local search screen has never been rendered natively; both require new native screenshots and recording. Do not accept the redesign from source inspection alone.

Use the ten-screen fixture at Tests/Fixtures/visual-reference.jpeg as the comparison target. Render at equal screen heights, inspect all edges/overlays, test real user covers and diverse aspect ratios, and compare every main experience rather than accepting isolated screens.

Physical iPhone Instruments traces, frame pacing, memory under a large library, battery, VoiceOver, and signing/playback behavior remain open gates. See QA.md and ../Verification/RESULTS.md.
