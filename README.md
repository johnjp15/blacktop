# Blackbar

A tiny macOS menu bar app that makes the menu bar black.

## How it works

The macOS menu bar is translucent over the desktop picture. Blackbar renders a
copy of each screen's wallpaper with a black strip exactly as tall as the menu
bar, and sets that as the wallpaper. macOS then draws the menu bar black and
switches its text to white. Turning it off restores your original wallpaper.

- Handles multiple displays and per-Space wallpapers (applied as you switch Spaces).
- Notices when you pick a new wallpaper and re-blackens it within a few seconds.
- Generated images live in `~/Library/Application Support/Blackbar/Wallpapers`.

## Limitations

- Still images only. Dynamic and Aerial wallpapers can't be read as a single image.
- If **Reduce transparency** is on (System Settings → Accessibility → Display),
  the menu bar is opaque and the wallpaper doesn't show through.

## Build

Requires macOS 14+ and the Xcode Command Line Tools (full Xcode not needed).

```sh
./scripts/build-app.sh
open build/Blackbar.app
```

For quick iteration without bundling: `swift run` (Launch at Login won't work this way).
