# MailCode

MailCode is a macOS app for watching configured mailboxes and surfacing verification codes in a small floating window.

## Features

- Supports common IMAP mail providers.
- Extracts verification codes from recent emails.
- Shows the latest code in the main window and an optional floating panel.
- Stores mailbox credentials in the macOS Keychain.
- Supports Sparkle-based update checks through the public GitHub release feed.

## Install

Download the latest `MailCode.dmg` from the [Releases](https://github.com/uncleshushushu-prog/MailCode/releases) page, open it, and drag `MailCode.app` into the Applications folder.

This app is currently distributed with ad-hoc signing. On first launch, macOS may show a developer verification warning. If that happens after moving the app to Applications, run:

```sh
xattr -dr com.apple.quarantine /Applications/MailCode.app
```

Then open MailCode from the Applications folder.

## Build

Open `MailCode.xcodeproj` in Xcode, or build from the command line:

```sh
xcodebuild -project MailCode.xcodeproj \
  -scheme MailCode \
  -configuration Release \
  -destination "generic/platform=macOS" \
  build
```

To produce a DMG:

```sh
./build_dist.sh
```

To generate and upload release assets:

```sh
./release_update.sh --upload
```

The release script creates:

- `MailCode.dmg`
- `appcast.xml`
- `update-feed.json`

## Updates

Sparkle reads the public appcast at:

```text
https://github.com/uncleshushushu-prog/MailCode/releases/latest/download/appcast.xml
```

## License

MIT. See [LICENSE](LICENSE).
