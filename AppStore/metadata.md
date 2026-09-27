# App Store Connect metadata — iClean

Everything needed to fill in the App Store Connect listing for the **1.0** release.
Character limits are noted; counts for the tight fields are given so nothing is
rejected on length. Where there are choices, the **recommended** value is first.

---

## App information

| Field | Value |
|-------|-------|
| **Bundle ID** | `com.shammas.iClean` |
| **Version** | 1.0 |
| **Primary category** | Photo & Video |
| **Secondary category** | Utilities |
| **Age rating** | 4+ (see questionnaire below) |
| **Copyright** | © 2026 Mohammed Shammas |
| **Price** | Free |

---

## Name (max 30)

**`iClean: Photo Cleanup`**  — 21 chars

Alternatives: `iClean – Free Up Space` (22) · `iClean: Clean Up Photos` (23)

## Subtitle (max 30)

**`Delete duplicates & clutter`**  — 27 chars

Alternatives: `Free up space, keep control` (27) · `Clean up photos, safely` (23)

## Promotional text (max 170 — editable anytime without review)

**`Free up storage without the worry. iClean finds duplicate, blurry, and screenshot photos plus big videos — and everything you delete is recoverable for 30 days.`**  — 160 chars

## Keywords (max 100, comma-separated, no spaces)

**`duplicate,cleaner,storage,space,delete,blurry,screenshot,declutter,gallery,icloud,organize,free`**  — 95 chars

(Don't repeat words already in the name — Apple indexes "iClean", "Photo", and
"Cleanup" from the title automatically.)

## Support URL

**https://mshammas.github.io/iClean/support**

## Marketing URL (optional)

Leave blank, or use https://mshammas.github.io/iClean/support

## Privacy Policy URL

**https://mshammas.github.io/iClean/privacy-policy**

---

## Description (max 4000)

```
Running out of space on your iPhone? iClean helps you clear it out — safely, and
without the stress. It looks through your photo library and gathers up the things
that are usually just taking up room, so you can delete them in a few taps.

WHAT ICLEAN FINDS
• Duplicates — copies of the same photo, so you can keep one and remove the rest.
• Blurry photos — shots that came out out-of-focus.
• Screenshots — the ones that pile up and are easy to forget.
• Large videos — the big files that quietly eat the most space.

BUILT TO BE SAFE
Deleting photos should never feel risky. iClean is careful on purpose:
• Nothing is ever deleted without you. You review everything and tap to confirm.
• Every deleted item goes to your Recently Deleted album and can be brought back
  for 30 days — nothing is gone for good right away.
• When it groups duplicates, it always keeps a copy for you.
• It only pre-selects photos it is confident about, and never your favourites.

PRIVATE BY DESIGN
Your photos are checked right here on your iPhone. Nothing about you or your
photos is ever uploaded, shared, or collected. There are no accounts, no ads,
and no tracking of any kind.

FREES UP ICLOUD TOO
Because your photos sync with iCloud, clearing them on your iPhone frees up the
space in iCloud as well.

SIMPLE TO USE
Large, clear text and plain language throughout — no clutter, no confusing menus.
Just scan, review, and clean up.

Requires iOS 17 or later.
```

---

## What's New (release notes for 1.0)

```
The first release of iClean. Scan your photo library for duplicates, blurry
shots, screenshots, and large videos, review what you'd like to remove, and free
up space — with everything recoverable for 30 days. Thanks for trying it.
```

---

## Age rating questionnaire

Answer **None / No** to every content question (no violence, no mature/suggestive
content, no profanity, no simulated gambling, no medical/drug references, no
horror, etc.). Result: **4+**.

- Unrestricted web access: **No**
- Made for Kids: **No** (leave the Kids category off)

---

## App Privacy (the nutrition label)

- **Data collection:** answer **"No, we do not collect data from this app."**
  → the label shows **Data Not Collected**.
- **Tracking:** No.

This matches the app's behaviour and the bundled `PrivacyInfo.xcprivacy` (no
tracking, no collected data types). Everything is processed on-device.

Step-by-step click path for this section: see `AppStore/app-privacy-clickpath.md`.

---

## Export compliance

Already declared in the build: `ITSAppUsesNonExemptEncryption = NO`. When asked
at upload, the answer is that the app uses no non-exempt encryption.

---

## Notes on the screenshots

Use the set in `AppStore/screenshots/` (the `captioned/` versions are recommended).
They show the **Blurry** category as the worked example, because duplicates,
screenshots, and large videos can't be reproduced in the simulator. If you want a
screenshot that shows the Duplicates screen specifically, it has to be captured on
a real device with a real library.
