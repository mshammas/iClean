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
- **Minimum iOS:** 17.0. (`IPHONEOS_DEPLOYMENT_TARGET = 17.0`.)
  Raised from 16.0 on 2026-07-19, forced by duplicate detection: Vision feature-print
  **revision 2 requires iOS 17**, and every calibrated duplicate threshold was measured on it.
  On iOS 16 the app silently fell back to revision 1, whose distances are ~74× larger — so a
  0.15 threshold matched essentially nothing and duplicate detection quietly did nothing at
  all. See `DetectionThresholds.visionFeaturePrintRevision`. The alternative was re-running the
  whole calibration on a second scale for the app's highest-stakes feature; the devices this
  drops are iPhone X and older (2017).
- **Device family:** iPhone only (`TARGETED_DEVICE_FAMILY = 1`), portrait only.
- **Detects four categories:** duplicates/near-duplicates, blurry photos, screenshots, large videos.
- **Deletion UX:** review list grouped by category → one prominent
  "Delete N items, free ~X GB" confirm button → single batch delete.
  **Duplicates additionally allow per-group deletion** ("Delete N now", behind a confirm alert),
  so a long review can be done in sittings instead of held in mind until the end. Note iOS shows
  its *own* system confirmation for every delete call, so per-group means more system prompts.
- **Default checked-for-deletion state:** only duplicate copies that are **near-certain**
  (feature-print distance ≤ `duplicateAutoTickMaxDistance` = 0.05) are pre-checked. Looser
  matches (0.05–0.15) are grouped and shown but start **unchecked**, and **favourites are never
  pre-checked**. Blurry / Screenshots / Large Videos are entirely opt-in. This is the safe
  default — deleting a wanted photo is the worst possible failure, so we bias against it.
- **Every duplicate group always keeps at least one copy.** The keeper is never a deletion
  candidate and has no tick box. The user can change *which* copy is kept ("Keep This One
  Instead"), which moves that protection rather than removing it.
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
      ScanProgress.swift             Sendable progress: phase (1 of 3…), scanned/total, optional
                                     sub-step `detail`, and an iCloud-scan flag
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
      FeatureDescriptor.swift        a Vision feature print as plain `[Float]`, plus the L2
                                     `distance(to:)`. Exists because a
                                     `VNFeaturePrintObservation` cannot be rebuilt from bytes
                                     (no public initialiser), so anything cached or passed
                                     around must be the raw descriptor. Verified bit-exact
                                     against Vision's own `computeDistance`.
      DuplicateGroup.swift           keeper + extras + why that copy was kept
    DeletionManager/
      DeletionManager.swift          re-fetch by ID, then one PHPhotoLibrary change block
      DeletionResult.swift           result + DeletionError with plain-language copy
    ReviewUI/
      CleanupFlowView.swift          owns NavigationStack + CleanupRoute + scan task + alerts
      CleanupViewModel.swift         scan lifecycle, selection, deletion; single alert channel.
                                     All deletion funnels through one private `delete(ids:)`,
                                     which records `deletedIDs` so already-deleted items vanish
                                     from every derived list (categories, groups, totals) —
                                     deleting mid-review must never leave rows pointing at
                                     photos that are gone.
      ReviewSelection.swift          value-type selection set keyed by localIdentifier
      HomeView.swift                 home: library counts + recent preview grid + Scan button
      HomeViewModel.swift            loads summary + recent assets for Home
      ScanningView.swift             progress + Stop while scanning
      ScanSummaryView.swift          category cards + the single Delete button
      CategoryReviewView.swift       per-category checklist + Tick All (LazyVStack — a category
                                     can hold thousands of rows; eager building swamps PhotoKit)
      DuplicateReviewView.swift      grouped review; leads with the keeper (no tick box on it).
                                     Which copy is kept is only a suggestion — "Keep This One
                                     Instead" in the viewer swaps it (`CleanupViewModel
                                     .makeKeeper`, tracked in `keeperOverrides`). The current
                                     keeper is never a deletion candidate, so **every group
                                     always keeps at least one copy** whatever the user ticks.
                                     Each group also has its own "Delete N now" (behind a
                                     confirm alert) so a long review can be done in pieces
                                     instead of one final batch.
      CandidateRow.swift             thumbnail (→ full screen) + reason + big tick box
      FullScreenAssetView.swift      full-screen viewer: pinch/double-tap zoom, video playback.
                                     Takes a `FullScreenSelection` (list + start id) and pages
                                     between items. In Duplicates, tapping any photo opens the
                                     **whole group** — keeper first, then copies — so the two
                                     can be swiped between and compared before confirming the
                                     deletion. A `FullScreenTarget` is either a deletion
                                     candidate (tick control) or the keeper (read-only).
                                     Laid out as a **column** (top bar / pager / bottom bar),
                                     never a ZStack — floating controls covered the photo the
                                     user was trying to judge. Each page shows the cached
                                     thumbnail instantly, then swaps in the full image, so a
                                     swipe never lands on a blank screen. Pan is high-priority
                                     only while zoomed, so at normal zoom the swipe reaches
                                     the pager.
      DeleteConfirmationView.swift   final gate: counts, size, 30-day safety net
      DeletionResultView.swift       success + where to find Recently Deleted
    Shared/
      Formatting.swift               ICFormat: count / fileSize / duration strings
      DesignSystem/
        Colors.swift                 ICColor semantic palette
        Typography.swift             ICTextStyle + .icStyle() — large, rounded, Dynamic Type
        AccessibleLayout.swift       `ICAdaptiveStack` (a row that becomes a column at the
                                     accessibility text sizes) and `.icIconSize(_:weight:)`
                                     (decorative-icon size that scales with Dynamic Type).
                                     Use these rather than a bare `HStack` for icon·text·control
                                     rows, and rather than `.font(.system(size:))` for symbols.
        Components/
          ICButton.swift             large full-width button (primary/secondary/destructive)
          ICInfoRow.swift            icon + title + detail explanatory row
          ICScreen.swift             standard scaffold: scroll content + pinned footer
    Assets.xcassets/                 AppIcon (placeholder), AccentColor (adaptive blue)
```

**Not yet built:** the scan cache store itself (M7 phases 3–6 — design agreed and recorded
below under "Scan cache design"; re-scans still recompute every measurement), and the M6 items
listed under "Current status".

### Architecture conventions
- One `@MainActor ObservableObject` ViewModel per screen (screens create their own).
- Heavy work (scanning, detection) lives in `actor` types, off the main thread, streaming progress.
- Cross-cutting state (onboarding + permission) lives in `AppState`, injected via `.environmentObject`.
- No DI framework; a small shared-object approach is enough.
- Design-system types are prefixed `IC` (ICColor, ICButton, ICScreen, ICTextStyle…).
- **Accessibility sizes are a supported layout, not a fallback.** Two rules follow from it, and
  both are easy to break by writing ordinary-looking SwiftUI:
  1. Never size a symbol with `.font(.system(size:))` — that is frozen and ignores Dynamic Type,
     so a 56pt hero icon becomes a speck beside AX5 text. Use `.icIconSize(_:)`.
  2. Never lay out icon·text·control as a plain `HStack` — at AX sizes the text column collapses
     to a few characters per line. Use `ICAdaptiveStack`, which switches to a `VStack` from AX1.
  Text that carries numbers (counts, sizes) also needs
  `.fixedSize(horizontal: false, vertical: true)` so it wraps rather than truncates — a
  truncated "Delete 262 items, free ~4.3 GB" hides exactly what the user is confirming.

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
xcrun simctl launch $SIM com.shammas.iClean
xcrun simctl io $SIM screenshot shot.png     # then read the PNG to inspect the UI
```

**Always compile before handing work back.** The project builds clean in Debug and Release.

**Simulator limitations:** `simctl privacy grant photos` does *not* make
`PHPhotoLibrary.authorizationStatus(for: .readWrite)` report `.authorized` — the app still shows
the primer. To reach Home in a simulator someone must tap "Allow Access" manually (AppleScript
taps need assistive access, which isn't available). Use
`xcrun simctl spawn $SIM defaults write com.shammas.iClean hasCompletedOnboarding -bool true`
to skip onboarding (writing the plist from the host does *not* work — cfprefsd owns it), and
`xcrun simctl addmedia $SIM <files>` to populate the library.
**Real photo-library behavior must still be verified on a physical iPhone.**

⚠️ **Do not `simctl erase` / `uninstall` to fix a launch failure.** Photo authorization is the
one piece of simulator state that cannot be restored from the command line, so erasing costs a
manual "Allow Access" tap to get back to Home — and that tap is the only way back.
(This was learned the hard way on 2026-07-19: the iPhone 17 simulator had authorization granted
and 12 test items, and an erase threw both away.) When `simctl launch` fails with
`FBSOpenApplicationServiceErrorDomain code=4`, the cause is almost always the **bundle ID**, not
simulator state — this project installs as **`com.shammas.iClean`**, not the `com.example.iClean`
in the project's default settings. Confirm with `xcrun simctl listapps $SIM | grep -i clean`.

To test Dynamic Type: `xcrun simctl ui $SIM content_size accessibility-extra-extra-extra-large`
(AX5), `accessibility-medium` (AX1), or `large` (default). Relaunch the app to pick it up.

---

## Detection approach (all four implemented)

Every threshold below was set by **measurement, not guesswork** — and two of them were wrong
until real-device data corrected them. Re-tune the same way: the `#if DEBUG` block in
`DetectionCoordinator` prints coverage, a blur-score histogram and a match-distance histogram
after each scan.


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
  separates 48.5× at far less decode cost than 1200/1600px.
  **Threshold is `blurVariance = 100`**, set from a real 17k-photo distribution (median 1390;
  ≤100 covers 3.7% of photos). An earlier value of 25, derived from *synthetic* Gaussian blur,
  was far too strict — it found 12 blurry photos in 17,000. Real blur scores higher because
  sensor noise and compression keep some high-frequency detail alive.
  Known false-positive mode: genuinely low-detail photos (clear sky, blank wall, very dark) —
  which is why blurry is never pre-ticked.
  Blur analysis runs with **`isNetworkAccessAllowed = false`**: scanning touches every photo,
  and these users often run "Optimise iPhone Storage", so downloads here could pull gigabytes.
  iCloud-only photos are skipped instead.
- **Duplicates** — `VNGenerateImageFeaturePrintRequest` at a **pinned revision 2**, compared
  with `FeatureDescriptor.distance(to:)` (plain L2, verified bit-exact against Vision's
  `computeDistance` — see that file for why we don't call Vision's version). Grouped at
  **≤ 0.15**, but only **pre-ticked at ≤ 0.05** (`duplicateAutoTickMaxDistance`).
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
  *Not yet implemented:* the descriptor cache (M7 phases 3–6) — re-scans still recompute every
  fingerprint. Design is agreed and recorded under "Scan cache design".
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
- **M1 — Enumeration + Home skeleton: DONE, device-verified.**
  `PhotoLibraryFetcher` counts the library off-main; Home shows total/photos/videos and a recent
  preview grid via `PhotoImageService` + `AssetThumbnailView`. "Scan My Photos" runs the real
  scan. Home re-reads its counts whenever a deletion happens, keyed on
  `CleanupViewModel.completedDeletions`.
- **M2 — Cheap detectors end-to-end: DONE, compile-verified. NOT yet behaviour-verified.**
  Screenshot + large-video detection, the full review flow (summary → per-category checklist →
  confirm → result), and real `PHPhotoLibrary` batch deletion. Screenshots and large videos start
  **unticked**, per the safety rule. Compiles clean in Debug + Release.
  **Verified on-device by the user (2026-07-19):** scan, review list, sizes, and the unticked
  default all behave correctly.
- **Full-screen viewer (post-M2, user-requested): DONE, device-verified and since reworked.**
  Tapping a row's thumbnail (magnifier badge marks it) opens `FullScreenAssetView`: pinch and
  double-tap zoom, video playback, and a tick control so the decision is made while looking at
  the item. Grown through three rounds of device feedback:
  1. the duplicate **keeper wasn't viewable at all** — it had no button; now tappable;
  2. **swipe-to-compare** across a whole duplicate group, since judging a duplicate means
     comparing it against the copy being kept;
  3. **layout and wording fixes** — controls were floating in a `ZStack` and covering the photo
     (now a column: top bar / pager / bottom bar), each page showed a blank while loading (now
     shows the cached thumbnail instantly, then swaps in the full image), and the two buttons
     read almost identically ("Keep This One" vs "Keep This One Instead" → the toggle is now
     "Don't Delete This One").
  ⚠️ The layout/wording round (3) is **compile-verified only** — not yet checked on device.
- **M3 — Blur detection: DONE, device-verified and calibrated on a real library.**
  `SharpnessAnalyzer` (Laplacian variance) + `BlurDetector` run as a **second scan pass** with
  bounded concurrency (6 at a time), reporting progress as "Step 2 of 3". The threshold and
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
- **M4 — Duplicate detection: DONE, fully device-verified (scan and review UI).**
  Feature-print detection, aspect/time pre-filtering, union-find clustering with keeper
  verification, and a grouped review screen. Scanning is now three passes.
  ⚠️ **This is the only category that pre-ticks items for deletion.**
  **Reviewed on device by the user (2026-07-19) — reported all good.** That closes what was the
  project's single biggest open risk: the pre-ticked copies are genuine duplicates and no
  favourite is pre-ticked. The `#if DEBUG` block prints group counts and a match-distance
  histogram if it ever needs re-checking.
  ⚠️ Still unanswered: whether the **0.05–0.15 band** (grouped but deliberately left unticked)
  holds real duplicates or distinct shots. That judgement decides whether
  `duplicateAutoTickMaxDistance` should move up from 0.05 — worth asking the user next time they
  are in the duplicates screen. The current value is the safe end regardless, so this is a
  recall question, not a safety one.
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
- **Duplicate review upgrades (post-M4, user-requested): DONE, compile-verified only.**
  All three came from device feedback and are **not yet device-verified**:
  - **Swipe-to-compare** — tapping any photo in a group opens the whole group in the viewer.
  - **Change the keeper** — "Keep This One Instead" (`CleanupViewModel.makeKeeper`, tracked in
    `keeperOverrides`). The app's pick is a suggestion; the user can move it.
  - **Per-group delete** — "Delete N now" on each group card, behind a confirm alert, so a long
    review can be done in pieces. All deletion funnels through one private
    `CleanupViewModel.delete(ids:)`, which records `deletedIDs`; every derived list filters
    those out so deleting mid-review can't leave rows pointing at photos that are gone.
- **M5 — Progress, cancellation, accessibility pass: DONE.**
  Progress and cancellation were already delivered under M3/M4 (`ScanProgress` with phase +
  `detail` sub-step, Stop honoured through fingerprinting *and* clustering). This milestone was
  therefore the **Dynamic Type pass**, which had never been done — VoiceOver labelling was
  already thorough, but nothing in the app responded to text size:
  - Added `ICAdaptiveStack` and `.icIconSize(_:)` (see Architecture conventions) and applied
    them across every icon·text·control row: `ICInfoRow`, `CandidateRow`, the summary category
    cards, the duplicate keeper row, and Home's photo/video stats.
  - `ICButton` labels now wrap instead of truncating, its minimum height scales, and its icon is
    dropped at accessibility sizes so the label gets the full width.
  - Thumbnails (`CandidateRow`, keeper row, Home grid) and Home's big library count now scale.
  **Verified in the simulator at AX1 and AX5** (Onboarding, Permission Primer) — info rows stack
  correctly, hero icons scale, button labels wrap, and the default text size is unchanged.
  ⚠️ The **review screens** (`CandidateRow`, category cards, duplicate groups) are
  **compile-verified only at accessibility sizes** — they sit behind photo authorization, which
  cannot be granted in the simulator (see Simulator limitations). Check those on device.
- **M6 — Edge cases: PARTIALLY DONE, compile-verified only.**
  - `CategoryReviewView` had **no empty state** — once a category emptied it showed a heading, a
    "Tick All" button and nothing else. It now shows a completion state, and the footer count
    and Tick All are hidden when there's nothing left.
  - **Limited Access wording.** `ScanSummaryView` now takes `hasLimitedAccess` and says it only
    checked the shared subset. Previously "We checked N items in your library" and "Your library
    is in good shape" were shown verbatim under Limited Access, which turns "we couldn't look"
    into a false all-clear — the same failure mode the blur coverage note exists to avoid.
  - **Empty library.** Home explained nothing when the library was empty; the Scan button was
    just disabled. It now says why (with different wording under Limited Access).
  - **Still outstanding:** re-scan-after-deletion edge cases, and iCloud-not-downloaded handling
    beyond the existing opt-in.
- **M7 — Scan cache: phase 1 of 6 DONE, compile-verified. NOT yet device-verified.**
  Goal: a re-scan shouldn't recompute what hasn't changed (13.5k fingerprints, 66s, every time).
  **Phase 1 deliberately ships alone**, because it is the only phase that can change detection
  results — so if group counts move, there is exactly one possible cause.
  - Pinned the Vision revision (fixing the iOS 16 bug described under Minimum iOS).
  - Replaced `VNFeaturePrintObservation` with `FeatureDescriptor` (`[Float]` + L2). Required for
    caching at all, since an observation can't be reconstructed from bytes.
  - Added a blur-pass timing heartbeat (`#if DEBUG`) matching the fingerprinting one.
  **Device run 2026-07-19 — phase 1 validated.** New baseline on a now-17,087-item library:
  229 groups, 239 extras, 256 matches, median 0.0896, **max 0.1498 (unchanged)**.
  The drop from 241/262/337 is accounted for by the user having deleted duplicates during the
  M4 device review — the library lost 21 photos and 8 videos, and removing one photo from a
  cluster of five removes four pairs, so −21 duplicate photos explains −81 matches. The
  `≤ 0.05` band fell 139 → 101, i.e. the *pre-ticked near-certain* copies are the ones gone,
  which is exactly what that review deletes.
  Two controls say the metric itself did not move: **max distance is identical to four decimal
  places**, and **blur (which shares the library and scan plumbing but not the distance code)
  did not shift** — median 1388 → 1390, `≤100` 3.7% → 3.5%, same distribution shape. Together
  with the bit-exact verification against Vision, the L2 swap and revision pin are clean.

---

## Scan cache design (M7) — agreed plan

A re-scan currently redoes everything: ~13.5k fingerprints (66s) plus the whole blur pass, even
when nothing changed. The fix is to memoize the two expensive per-photo *measurements*.

**Measured facts** (don't re-derive these; they were established by experiment on 2026-07-19):

| Fact | Value |
|---|---|
| Feature print, revision 2 | 768 × Float32 = 3,072 B |
| `computeDistance` | exactly L2 over the descriptor — verified bit-exact |
| Descriptors are already fp16 | 100% of elements round-trip through `Float16` losslessly |
| Cache projection @ 13.5k photos | **~21 MB** prints (fp16) + **<1 MB** blur scores |

**Principles.**
- **Cache the measurement, not the verdict.** Store raw blur scores and raw descriptors, never
  "is blurry" / "is a duplicate". Re-tuning `blurVariance` or `duplicateAutoTickMaxDistance`
  then costs a re-classify rather than a full re-scan — which matters while the 0.05 question
  is still open.
- **Cache successes only.** Never persist `couldNotLoad` / `deliveredTooSmall`. That set is
  volatile — it is the *resolution-availability* limit (256px available for all 13,551 photos,
  800px missing for 4,995), and iOS moves originals in and out as storage pressure changes.
  Caching a failure would permanently blind the app to a photo that later becomes checkable.
- **Store fp16.** Lossless here, and it halves the cache. Guard it with a debug assertion that
  the round-trip is exact, falling back to Float32 if it ever isn't.

**Storage.** SQLite via the raw `sqlite3` C API (no dependency), in Application Support with
`isExcludedFromBackup = true` — a regenerable cache must never eat the user's iCloud backup,
least of all in this app. Tables: `meta(key,value)`, `blur(local_id PK, modified, score)`,
`print(local_id PK, modified, vec)`.

**Invalidation.** Key on `localIdentifier` + `modificationDate`. Version-stamp blur on
`blurAnalysisDimension`/`blurTileSize`/`blurTilePercentile`, prints on
`duplicateAnalysisDimension`/`visionFeaturePrintRevision`/precision. A mismatch drops only the
affected table. Prune rows whose identifiers have left the library.
Note `modificationDate` also changes on non-pixel edits (favouriting) → needless recompute:
wasteful, never stale, which is the safe direction. After a device restore `localIdentifier`
can change wholesale → total miss, self-healing via prune.

**Measured pass costs** (device, 2026-07-19, 17,087-item library — this is what the cache is
aimed at, so don't re-derive it):

| Pass | Items | Time | Share |
|---|---|---|---|
| Blur | 11,818 processed · 4,175 actually measured | **149s** | ~63% |
| Fingerprint | 13,530 | **87s** | ~37% |
| Compare | 13,530 | <1s | ~0% |

**Blur is the larger cost and the cheaper thing to cache** (<1 MB of scores vs ~21 MB of
descriptors), which is why phase 4 precedes phase 5. Fingerprinting is 6.4ms/photo at 256px;
blur is 800px (~9.8× the pixels), so the 4,175 real measurements plausibly account for ~125s of
the 149s and the 4,974 failed loads are comparatively cheap. **Not yet decomposed** — worth
per-outcome timing before assuming how much of the blur pass a cache actually recovers, since
failed loads are re-attempted every scan by design (see "cache successes only").

**Phases.** 1 ✅ pin revision + `FeatureDescriptor` · 2 ✅ blur timing · 3 cache store
(SQLite, versioning, pruning, backup exclusion) · 4 wire blur scores · 5 wire descriptors
· 6 storage visibility + "Clear cached scan data".

**Re-scan UX: transparent.** No new screens or concepts — the scan simply finishes faster.

## Where to pick up

In rough priority order:

Everything at the top of this list is a **device check** — the code below it is written but
unexercised, and stacking more on top of unverified UI is the pattern to avoid here.

1. **M7 phases 3–6** — the cache store, then blur scores, then descriptors, then storage
   visibility. Phase 1 is validated and the pass costs are measured (see "Scan cache design");
   this is now unblocked and is the largest single improvement available (a ~4 min scan should
   drop to seconds on re-scan).
2. **Verify the review screens at a large text size on device** (Settings → Display & Brightness
   → Text Size, or Accessibility → Larger Text for the AX range). The M5 pass is verified in the
   simulator only for Onboarding and the Permission Primer; `CandidateRow`, the summary category
   cards and the duplicate group cards sit behind photo authorization, which the simulator
   cannot grant. Check the tick boxes are still reachable and rows still read as rows.
3. **Verify the reworked full-screen viewer** — photo fully visible between the bars, swiping
   feels smooth, and the two buttons read distinctly.
4. **Verify the new M6 states** — empty category after deleting everything in it, and the
   Limited Access wording (share only a few photos with iClean, then scan).
5. **The iCloud opt-in ("Check Those Too") has never been run.** Needs a Wi-Fi test, and a check
   that Stop still responds mid-download.
6. **Finish M6** — re-scan-after-deletion edge cases.
7. **Ask about the 0.05–0.15 duplicate band** while in the duplicates screen: are those genuine
   duplicates or distinct shots? That answer decides whether `duplicateAutoTickMaxDistance`
   should rise above 0.05. Now the *majority* band: of 256 matches, 101 are ≤0.05 and 118 sit
   in 0.10–0.15.
8. *Optional:* merge the blur and duplicate passes into a single image load (~45% less pixel
   work). Deliberately not done — scan time is currently acceptable (~66s of fingerprinting on a
   17k library) and it isn't worth destabilising the highest-stakes code for speed.

## Repository

`git@github.com:mshammas/iClean.git`, branch `main`.

⚠️ This machine has **two GitHub accounts**. The remote must use the SSH host alias from
`~/.ssh/config` — `git@github-mshammas:mshammas/iClean.git` — **not** plain `github.com`, which
picks the wrong key and fails with "Permission … denied to ichummas".
Verify with `ssh -T git@github-mshammas` (should greet "Hi mshammas!").

The full milestone plan lives at
`/Users/shammas/.claude/plans/this-repo-is-for-wondrous-naur.md`.
