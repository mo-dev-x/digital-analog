# Free installation and refresh

## Build versus install

A macOS/Xcode environment builds the native application. It can be a borrowed Mac or an authorized GitHub Actions macOS runner. Windows/Linux signing tools do not compile SwiftUI source. A generated unsigned IPA still requires signing before installation.

No Apple credentials are needed for the supplied unsigned CI build. Sign on your own trusted device/computer; do not put Apple Account passwords in CI secrets or send them in chat.

## Preferred routes

### SideStore

1. Follow the current official prerequisites: https://docs.sidestore.io/docs/installation/prerequisites
2. Initially pair/install using iloader from a supported Windows, macOS or Linux computer.
3. Install LocalDevVPN, connect Wi-Fi, import the pairing material and finish the first refresh as instructed by SideStore.
4. Import the built IPA and sign it with your own Apple Account.
5. Enable the supported background refresh workflow and verify an actual renewal before relying on it. Periodically check the expiry counter. Use manual refresh as recovery.

Your personal computer need not remain powered on. Signing still uses Apple's services and SideStore's supported anisette infrastructure. Pairing can need repair after iOS updates/reset; free app/App-ID limits still apply. If the signing application expires, a computer may be needed to reinstall it.

### Current AltStore Classic

Follow https://faq.altstore.io/altstore-classic/remote-altservers

Current Classic versions provide a Remote AltServer workflow. Initial computer pairing and LocalDevVPN setup are required; afterward Wi-Fi plus LocalDevVPN permits refresh without a running personal AltServer. Check remote-service availability and verify background/manual refresh on the actual phone. The ordinary desktop AltServer workflow remains a fallback.

### Xcode Personal Team

Select your team and phone, build and Run. Free profiles expire after seven days. Keep the same team/bundle ID for renewals. This is straightforward for development but generally requires periodic Mac access.

### Other options

Sideloadly offers a desktop refresh daemon, useful if you have periodic computer access. TrollStore is restricted to supported historical iOS versions and is not assumed available. No jailbreak, paid certificate seller or enterprise-certificate dependency is part of this project.

## Expiry/data recovery

- Export a collection backup before changing signing tools/team or reinstalling.
- Refresh before expiry; an expired signature can block the whole app, even though audio files are offline.
- Re-sign/install over the existing app using the same identity where supported. Do not delete the existing app to try fixing a signing failure unless you have a verified backup.
- After installation, test one renewal, an offline relaunch and a locked playback session.
