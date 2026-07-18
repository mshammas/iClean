# CLAUDE.md — iClean

> **Purpose of this file:** the single source of truth for the iClean project so any new
> session can get full context without relying on chat history. If you are an AI assistant
> starting fresh, read this top to bottom first.

> **⚠️ SELF-MAINTENANCE RULE (do this every time):** Whenever you make a change that affects
> anything documented here — architecture, scope, product decisions, folder structure,
> build/run steps, milestone status, or known constraints — **update the relevant section of
> this file in the same change.** Keep it accurate and concise. Treat an out-of-date CLAUDE.md
> as a bug. When you finish a milestone, update "Current status". When you add a new source
> folder or major type, update "Project structure". Do not let this file drift from reality.

---

## What iClean is

A **native iOS app** that helps people reclaim iCloud storage by finding and deleting unwanted
photos and videos. It scans the photo library on-device, buckets clutter into categories
(duplicates, blurry photos, screenshots, large videos), lets the user review and confirm, then
deletes the chosen items (which go to iOS's Recently Deleted album, syncing the deletion to iCloud).

**Target audience: skews elderly.** The interface must be intuitive, large-text, high-contrast,
shallow (no deep menus), plain-language, and hard to make an irreversible mistake with. This is a
first-class product constraint, not a nice-to-have.

### Key technical reality
There is **no third-party "iCloud Photos API."** The only supported way to read/delete a user's
iCloud photos is Apple's **PhotoKit** framework, on-device. PhotoKit works against the local view
of the user's iCloud-synced library, and deletions sync back to iCloud automatically. This is why
iClean is a native iOS app, not a script or web service.

---

## Confirmed product decisions

- **Stack:** Swift / SwiftUI, MVVM. Single app target.
- **Minimum iOS:** 16.0. (`IPHONEOS_DEPLOYMENT_TARGET = 16.0`.)
- **Device family:** iPhone only (`TARGETED_DEVICE_FAMILY = 1`), portrait only.
- **Detects four categories:** duplicates/near-duplicates, blurry photos, screenshots, large videos.
- **Deletion UX:** review list grouped by category → one prominent
  "Delete N items, free ~X GB" confirm button → single batch delete.
- **Default checked-for-deletion state:** ONLY the non-"best" copies inside duplicate groups are
  pre-checked. Blurry / Screenshots / Large Videos start **unchecked** (opt-in). This is the safe
  default — deleting a wanted photo is the worst possible failure, so we bias against it.
- **Safety net:** iOS's built-in **Recently Deleted (30-day)** album. We do **NOT** build an
  in-app trash/undo — Recently Deleted is the backstop, and the UI copy says so plainly.
- **Privacy:** all analysis is on-device. Nothing is uploaded. Say this in user-facing copy.

---

## Project structure

Single SwiftUI target. The Xcode project uses a **file-system-synchronized root group**
(Xcode 16, `objectVersion = 77`), so **any file added under `iClean/` is automatically part of the
target — you never edit `project.pbxproj` to add a Swift file.** Just create the file in the right
folder.

```
iClean/                              repo root
  CLAUDE.md                          this file
  iClean.xcodeproj/                  hand-authored project (synchronized groups)
  iClean/                            all source (synchronized into the target)
    iCleanApp.swift                  @main entry
    App/
      AppState.swift                 top-level ObservableObject; computes AppStage routing
      RootView.swift                 routes by AppStage; UIKit side effects (settings, limited picker)
      OnboardingView.swift           first-run welcome
    Permissions/
      PhotoLibraryAuthorizationManager.swift   wraps PHPhotoLibrary auth, @Published status
      PermissionPrimerView.swift     pre-prompt explainer
      PermissionDeniedView.swift     denied/restricted → Settings deep link
      LimitedAccessBanner.swift      shown on Home when access is .limited
    PhotoLibraryScanning/
      LibrarySummary.swift           Sendable snapshot: photo/video counts
      PhotoLibraryFetcher.swift      reads library off-main: counts, recent assets, full fetch
      PhotoImageService.swift        shared PHCachingImageManager → thumbnails, full-screen
                                     images (capped at 2400px), and video player items
      AssetThumbnailView.swift       square async thumbnail w/ video-duration badge
      AssetResourceInfo.swift        file size via PHAssetResource KVC + safe fallback estimate
      ScanProgress.swift             Sendable scan progress (scanned/total, status text)
    DetectionEngine/
      Candidate.swift                CleanupCategory (+ user-facing copy) and Candidate model
      ScanResults.swift              scan output: per-category lookup, totals, default ticks
      DetectionThresholds.swift      all tunable constants (sizes, durations, batch size)
      DetectionCoordinator.swift     actor: batched, cancellable scan streaming ScanProgress
      SharpnessAnalyzer.swift        per-tile Laplacian variance, 90th percentile across tiles
      Strategies/
        ScreenshotDetector.swift     metadata-only: .photoScreenshot
        LargeVideoDetector.swift     size/duration thresholds + screen recordings
        BlurDetector.swift           async pixel pass; skips screenshots, videos, Portrait-mode
                                     shots, iCloud-only, and undersized deliveries
        DuplicateDetector.swift      Vision feature prints → aspect/time pre-filter →
                                     union-find → keeper verification; the only pre-ticking one
      DuplicateGroup.swift           keeper + extras + why that copy was kept
    DeletionManager/
      DeletionManager.swift          re-fetch by ID, then one PHPhotoLibrary change block
      DeletionResult.swift           result + DeletionError with plain-language copy
    ReviewUI/
      CleanupFlowView.swift          owns NavigationStack + CleanupRoute + scan task + alerts
      CleanupViewModel.swift         scan lifecycle, selection, deletion; single alert channel
      ReviewSelection.swift          value-type selection set keyed by localIdentifier
      HomeView.swift                 home: library counts + recent preview grid + Scan button
      HomeViewModel.swift            loads summary + recent assets for Home
      ScanningView.swift             progress + Stop while scanning
      ScanSummaryView.swift          category cards + the single Delete button
      CategoryReviewView.swift       per-category checklist + Tick All (LazyVStack — a category
                                     can hold thousands of rows; eager building swamps PhotoKit)
      DuplicateReviewView.swift      grouped review; leads with the keeper (no tick box on it)
      CandidateRow.swift             thumbnail (→ full screen) + reason + big tick box
      FullScreenAssetView.swift      full-screen viewer: pinch/double-tap zoom, video playback,
                                     tick control; opened by tapping a row's thumbnail
      DeleteConfirmationView.swift   final gate: counts, size, 30-day safety net
      DeletionResultView.swift       success + where to find Recently Deleted
    Shared/
      Formatting.swift               ICFormat: count / fileSize / duration strings
      DesignSystem/
        Colors.swift                 ICColor semantic palette
        Typography.swift             ICTextStyle + .icStyle() — large, rounded, Dynamic Type
        Components/
          ICButton.swift             large full-width button (primary/secondary/destructive)
          ICInfoRow.swift            icon + title + detail explanatory row
          ICScreen.swift             standard scaffold: scroll content + pinned footer
    Assets.xcassets/                 AppIcon (placeholder), AccentColor (adaptive blue)
```

**Still to come (later milestones):** `Strategies/BlurDetector.swift` (M3);
`Strategies/DuplicateDetector.swift`, `DuplicateGroup.swift`, `DuplicateGroupView.swift`,
and the on-disk feature-print cache (M4).

### Architecture conventions
- One `@MainActor ObservableObject` ViewModel per screen (screens create their own).
- Heavy work (scanning, detection) lives in `actor` types, off the main thread, streaming progress.
- Cross-cutting state (onboarding + permission) lives in `AppState`, injected via `.environmentObject`.
- No DI framework; a small shared-object approach is enough.
- Design-system types are prefixed `IC` (ICColor, ICButton, ICScreen, ICTextStyle…).

---

## Permission flow (implemented)

Request `.readWrite` up front (read to scan, write to delete). `AppState.stage` routes:
`onboarding` → `permissionPrimer` → (`home` if authorized/limited | `permissionDenied` if
denied/restricted). Status is re-checked on `scenePhase == .active` (user may change it in Settings).
`.limited` access still lands on Home but shows `LimitedAccessBanner` with a "Choose More Photos"
button (`presentLimitedLibraryPicker`). Usage-description strings live in the target build settings
as `INFOPLIST_KEY_NSPhotoLibraryUsageDescription` (Info.plist is auto-generated).

---

## Build & run

**This is an Xcode project — build and run from Xcode, not the command line.**

1. Open `iClean.xcodeproj` in **Xcode 16 or newer** (the project uses file-system-synchronized
   groups / `objectVersion 77`). Verified working on **Xcode 26.6**.
2. Select the **iClean** target → **Signing & Capabilities** → pick your Team (a free Apple ID
   works) and change **Bundle Identifier** from `com.example.iClean` to something unique to you
   (e.g. `com.<yourname>.iClean`), or signing will fail.
3. Choose your connected iPhone as the run destination and press Run. Photo-library behavior can't
   be meaningfully tested in the Simulator — use a real device.

### Developer-account note
On a **free** Apple ID, the installed app **expires after 7 days** and must be re-run from Xcode to
reinstall. This is expected, not a bug. TestFlight/App Store distribution and some capabilities
require the **paid** Apple Developer Program ($99/yr) — upgrade before any wider distribution.

### Environment note for AI assistants — you CAN build and run
**Xcode 26.6 is installed** at `/Applications/Xcode.app` (iOS 26.5 SDK). However,
`xcode-select -p` still points at `/Library/Developer/CommandLineTools`, so `xcodebuild` fails
unless you override the developer dir per command:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

# Compile check (fast, no signing needed):
xcodebuild -project iClean.xcodeproj -scheme iClean \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|warning:|BUILD"

# Run in a simulator:
SIM=$(xcrun simctl list devices available | grep -m1 "iPhone 17 (" | grep -oE "[0-9A-F-]{36}")
xcrun simctl boot $SIM; xcrun simctl install $SIM <path-to-iClean.app>
xcrun simctl launch $SIM com.example.iClean
xcrun simctl io $SIM screenshot shot.png     # then read the PNG to inspect the UI
```

**Always compile before handing work back.** The project builds clean in Debug and Release.

**Simulator limitations:** `simctl privacy grant photos` does *not* make
`PHPhotoLibrary.authorizationStatus(for: .readWrite)` report `.authorized` — the app still shows
the primer. To reach Home in a simulator someone must tap "Allow Access" manually (AppleScript
taps need assistive access, which isn't available). Use
`xcrun simctl spawn $SIM defaults write com.example.iClean hasCompletedOnboarding -bool true`
to skip onboarding (writing the plist from the host does *not* work — cfprefsd owns it), and
`xcrun simctl addmedia $SIM <files>` to populate the library.
**Real photo-library behavior must still be verified on a physical iPhone.**

---

## Detection approach (reference for upcoming milestones)

- **Screenshots** — metadata only: `asset.mediaSubtypes.contains(.photoScreenshot)`.
- **Large videos** — `mediaType == .video`; size via `PHAssetResource` `fileSize` (verify API;
  fall back to duration × bitrate). Flag over size/duration thresholds or `.videoScreenRecording`.
- **Blur** — Laplacian variance on the luminance of an image downscaled to **800px**, scored
  **per 128px tile** with the 90th percentile taken across tiles (not a whole-image average).
  Whole-image averaging punishes photos *meant* to contain blur — Portrait mode, macro,
  shallow depth of field — and photos with large plain areas like sky. Tiling asks "is any
  meaningful part of this in focus?" instead. Measured: sharp 718, Portrait-style 116–495
  (even with the subject at 25% of frame), genuinely blurred 3–12.
  **Portrait-mode photos (`.photoDepthEffect`) are skipped outright** as well — a deliberately
  blurred background deserves a guarantee, not a statistical margin.
  That dimension was chosen by measurement (see `DetectionThresholds.blurAnalysisDimension`):
  downscaling destroys blur, so at 400px sharp-vs-blurry separated only 6.8×, while 800px
  separates 48.5× at far less decode cost than 1200/1600px. Sharp photos measured 400–5300,
  clearly blurry ones 2–8, so the threshold sits at 25. Known false-positive mode: genuinely
  low-detail photos (clear sky, blank wall, very dark) — which is why blurry is never pre-ticked.
  Blur analysis runs with **`isNetworkAccessAllowed = false`**: scanning touches every photo,
  and these users often run "Optimise iPhone Storage", so downloads here could pull gigabytes.
  iCloud-only photos are skipped instead.
- **Duplicates** — `VNGenerateImageFeaturePrintRequest` + `computeDistance` at **≤ 0.15**.
  Calibrated by measurement: near-duplicates score 0.00–0.19 (identical 0.0, re-encoded 0.006,
  resized 0.014, cropped-90% 0.126, rotated-2° 0.163) while unrelated photos bottom out at
  **0.4163** — and a brightness-edited copy scores 0.433, i.e. the ranges *overlap* near 0.4.
  0.15 keeps ~2.8× margin below the unrelated floor. Recall is deliberately sacrificed:
  filtered/heavily-edited copies aren't grouped.
  Pre-filters: same aspect ratio (±0.02) and taken within 1 hour, to avoid O(n²).
  Clustering is union-find, **then every extra is re-verified against the keeper** — single
  linkage would chain A≈B≈C into one group without A≈C, which could pre-tick a genuinely
  different photo. Keeper priority: `isFavorite` → resolution → file size → oldest.
  **Favourites are never pre-ticked**, even as extras (`Candidate.preselect`).
  *Not yet implemented:* on-disk feature-print cache keyed by `localIdentifier` +
  `modificationDate` (re-scans currently recompute everything).
- **Scanning** — enumerate `PHFetchResult` lazily in batches on a background actor; request only
  **downscaled** images for analysis (never full-res); run cheap passes first; stream progress;
  fully cancellable. Watch for **Limited access** (subset only) and **iCloud-not-downloaded**
  originals (can trigger heavy network downloads — request small sizes, consider a Wi-Fi/opt-in gate).

---

## Current status

- **M0 — Scaffolding + permission flow: DONE, build-verified.** Compiles clean (Debug + Release)
  on Xcode 26.6; app launches in the simulator, Onboarding and Permission Primer render correctly
  and stage routing works. Xcode project, folder structure, Info.plist keys, design system,
  onboarding, and the full permission flow (primer / denied / limited) are in place.
- **M1 — Enumeration + Home skeleton: DONE, compile-verified.**
  `PhotoLibraryFetcher` counts the library off-main; Home shows total/photos/videos and a recent
  preview grid via `PhotoImageService` + `AssetThumbnailView`. The "Scan My Photos" button exists
  but currently shows a "coming soon" alert — real detection lands in M2.
  **Home screen not yet visually verified** — reaching it needs a real photo-permission grant
  (see simulator limitations above). Verify on the physical iPhone.
- **M2 — Cheap detectors end-to-end: DONE, compile-verified. NOT yet behaviour-verified.**
  Screenshot + large-video detection, the full review flow (summary → per-category checklist →
  confirm → result), and real `PHPhotoLibrary` batch deletion. Screenshots and large videos start
  **unticked**, per the safety rule. Compiles clean in Debug + Release.
  **Verified on-device by the user (2026-07-19):** scan, review list, sizes, and the unticked
  default all behave correctly.
- **Full-screen viewer (post-M2 addition, user-requested): DONE, compile-verified only.**
  Tapping a row's thumbnail (magnifier badge marks it) opens `FullScreenAssetView`: pinch and
  double-tap zoom for photos, playback for videos, and a tick control so the decision can be made
  while looking at the item. Not yet verified on device.
- **M3 — Blur detection: DONE, device-verified and calibrated on a real library.**
  `SharpnessAnalyzer` (Laplacian variance) + `BlurDetector` run as a **second scan pass** with
  bounded concurrency (6 at a time), reporting progress as "Step 2 of 2". The threshold and
  analysis dimension were calibrated by running the real pipeline over sharp vs progressively
  blurred photographs (see Detection approach above) rather than guessed.
  Portrait-mode photos are excluded two ways (metadata skip + per-tile scoring).
  **Device-calibrated (2026-07-19)** against a real 17,116-item library:

      library items 17,116 · eligible for blur 11,847
        measured 4,177 · no image 4,995 · too small 0 · Portrait skipped 2,675
        blurry found 12 at threshold 25

  Two findings. **(1) The threshold was far too strict** — synthetic Gaussian blur had
  mis-calibrated it; real blurry photos score higher because noise/compression preserve
  high-frequency detail. Raised 25 → 100 from the measured distribution (see
  `DetectionThresholds.blurVariance`), taking it from 0.3% to ~3.7% of photos —
  **confirmed on device: 153 flagged, exactly matching the ≤100 bucket.** User verified the
  flagged photos are genuinely blurry and that **no Portrait shots appear** — validating both
  the `.photoDepthEffect` skip and the tiled scoring against 2,675 Portraits in that library.
  Threshold settled at 100. The far (least-blurry) end of the list was not eyeballed, which is
  an accepted risk: blurry is never pre-ticked, is sorted blurriest-first, and every item is
  reviewable full-screen, so a loose threshold costs a scroll rather than a photo. Re-tune with
  the `#if DEBUG` histogram if real use shows junk at the tail.
  **(2) Coverage gap: 4,995 photos (42% of eligible) could not be analysed at all** because
  they're iCloud-only and downloads are off by default. Addressed with an **opt-in**: the
  summary's coverage note carries a "Check Those Too" button which, after an alert warning
  about data use and advising Wi-Fi, re-runs the scan with `includeICloudPhotos: true`.
  Downloads remain **off by default** and only ever enable through that explicit choice;
  the scanning screen says "including photos from iCloud" so the longer wait is explained.
  The size guard was exonerated (0 rejections). A `#if DEBUG` block in `DetectionCoordinator`
  prints coverage + a score histogram after each scan — the tool to use for any re-tuning.
  Supporting changes: `CategoryReviewView` uses `LazyVStack`; blurry results sort
  **blurriest-first** via `Candidate.detectionScore`, so debatable calls sit at the list's end.
- **M4 — Duplicate detection: DONE, compile-verified + threshold calibrated. NOT device-verified.**
  Feature-print detection, aspect/time pre-filtering, union-find clustering with keeper
  verification, and a grouped review screen. Scanning is now three passes.
  ⚠️ **This is the only category that pre-ticks items for deletion**, so device verification
  matters more here than anywhere else: confirm every group really is the same photo, and that
  no favourite is ever pre-ticked. The `#if DEBUG` block prints group counts and a match-distance
  histogram — if match distances cluster near 0.15 rather than near 0, tighten the threshold.
  ⚠️ **Known cost:** the duplicate pass loads every photo again, on top of the blur pass. A
  combined single-load pass would cut the pixel work ~45% if scans feel slow.
  **Device test (2026-07-19) — appeared frozen** on "Step 2 of 3, 11,839 of 11,839". Three
  compounding causes, all fixed: (a) no progress was emitted when pass 3 began, so the UI held
  pass 2's final state; (b) the clustering stage reported no progress **and never checked for
  cancellation**, so Stop was dead during it; (c) clustering could go O(n²) — bulk-imported
  photos (messaging apps, downloads) share near-identical creation dates, so thousands land in
  one time window. Now bounded by `duplicateMaxNeighbourComparisons = 200`, with progress and
  cancellation checks every 50 photos, and a `detail` sub-step on `ScanProgress`
  ("looking at each photo" / "comparing photos").
  **Second device test — still stuck**, now at "Step 3 of 3, 0 of 13,551": a hang in the very
  first batch, not slowness. Cause: `VNImageRequestHandler.perform` is **synchronous and
  blocking**, and running several inside async tasks occupied every Swift cooperative-pool
  thread, leaving the PhotoKit continuations no thread to resume on. Vision now runs on a
  dedicated `DispatchQueue` (`DuplicateDetector.visionQueue`) so the pool stays free.
  ⚠️ **General rule for this codebase: never call blocking synchronous framework APIs
  (Vision, ImageIO) directly inside async tasks — hand them to a dispatch queue.**
  Debug heartbeats now print fingerprinting/comparison rate so "slow" and "hung" are
  distinguishable from the console alone.
  **Third device test — completed successfully.** 13,551 fingerprints in 66s (~205/sec);
  comparison under 1s (the neighbour cap works); 241 groups, 262 extras.
  Two findings acted on:
  - **Match distances had a risky tail**: median 0.067, but 138 of 337 matches sat in
    0.10–0.15 (max 0.1498, i.e. right on the threshold) — the band where crops/variations
    live, not true copies. Rather than move `duplicateMaxDistance`, added a **second tier**:
    `duplicateAutoTickMaxDistance = 0.05`. Matches beyond it are still grouped and shown, but
    start **unticked**. So the app only ever auto-proposes deletion for near-certain copies.
  - **`could not fingerprint` was 0 for all 13,551**, while the blur pass couldn't load 4,995.
    The difference is the requested size: 256px is available locally for every photo, 800px is
    not. So the blur "coverage gap" is a *resolution availability* limit, not photos being
    absent from the device — worth remembering before attributing it to iCloud alone.
- **M5/M6 — Progress, cancellation, accessibility pass, edge cases:** not started.

The full milestone plan lives at
`/Users/shammas/.claude/plans/this-repo-is-for-wondrous-naur.md`.
