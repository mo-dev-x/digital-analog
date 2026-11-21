# Verification results

## 2026-11-21: GitHub Actions, macOS 15 (public local-library edition)

| Check | Result |
| --- | --- |
| Unsigned device build (Release, generic iOS) | Build succeeded |
| Swift core tests (`scripts/test.sh`) | Passed |
| Simulator collection tests | 8 passed, 0 failed |
| Live artwork provider and offline import (MusicBrainz / Cover Art Archive) | 1 passed; depends on live services, so it is reported but not required |
| UI journey tests | 2 passed, 0 failed |

Not yet verified: installation on a physical iPhone, signing and refresh, long locked playback, measured device performance.
