# App Store screenshots

All images are **1320 × 2868** — the iPhone 6.9" display size, currently the only
iPhone size App Store Connect requires. Captured on the iPhone 17 Pro Max simulator
with the classic 9:41 status bar.

- **`raw/`** — clean device screenshots, no caption. Uploadable as-is.
- **`captioned/`** — marketing versions: a headline over a framed screenshot on a
  soft-blue background, using the app's own SF Rounded font. Most stores convert
  better with these.

Upload **one** set (usually `captioned/`), in the numbered order.

| # | Screen | Headline (captioned) |
|---|--------|----------------------|
| 01 | Onboarding | Free up space in minutes |
| 02 | Permission / privacy | Your photos never leave your iPhone |
| 03 | Home | Your whole library at a glance |
| 04 | Scan results | Finds what's worth deleting |
| 05 | Category review | You decide what goes |
| 06 | Full-screen viewer | Check every shot up close |
| 07 | Delete confirmation | Nothing's gone for 30 days |

## Notes

- The example clutter shown is the **Blurry Photos** category (three defocused test
  photos). Duplicates, screenshots, and large videos couldn't be populated in the
  simulator — duplicate detection needs Vision, which doesn't run there. On a real
  device with a real library, the results screen would show all four categories.
- To regenerate: capture the raw screens on an iPhone 6.9" simulator with
  `xcrun simctl status_bar <udid> override --time "9:41" --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4`,
  then re-run the captioning composite (headlines + `SFNSRounded.ttf` on a blue gradient).
