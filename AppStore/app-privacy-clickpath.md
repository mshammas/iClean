# App Store Connect — App Privacy click path

How to fill in the **App Privacy** section (the "nutrition label") for iClean.
Because iClean collects no data and does no tracking, this is the short path:
you declare "no data collected" and there are no follow-up data-type questions.

> UI wording in App Store Connect shifts over time — button labels may differ
> slightly from what's written here, but the choices are the same.

## Before you start
- You need the **paid** Apple Developer Program membership and the iClean app
  record already created in App Store Connect (Bundle ID `com.shammas.iClean`).
- App Privacy is set at the **app level** (not per version), and must be
  **Published** before you can submit a build for review.

## Steps

1. Sign in to **appstoreconnect.apple.com** → **Apps** → **iClean**.
2. In the left sidebar, under **General**, click **App Privacy**.
3. **Privacy Policy URL** — click **Edit** next to it and enter:
   `https://mshammas.github.io/iClean/privacy-policy` → **Save**.
4. Find the **Data Collection** section and click **Get Started** (first time) or
   **Edit**.
5. You'll be asked: **"Do you or your third-party partners collect data from this
   app?"** Choose:
   > **No, we do not collect data from this app**

   This is correct: iClean does all analysis on-device, has no servers, no
   accounts, and bundles no third-party SDKs.
6. Because you chose **No**, there are **no further questions** — no data types,
   no tracking questions. Click **Save**.
7. Back on the App Privacy page, click **Publish** (top right) and confirm.
8. Verify the label preview now reads **"Data Not Collected."**

## After publishing
- The public product page will show a **Data Not Collected** privacy card.
- This is your strongest listing differentiator — leave it accurate.

## Important caveats
- The "No" declaration covers **you and any third-party code**. It's true today
  because iClean has zero SDKs. **If you ever add analytics, crash reporting, ads,
  or any SDK that phones home, you must come back and update this** — an
  inaccurate label is grounds for rejection or removal.
- This App Privacy label is **separate** from the `PrivacyInfo.xcprivacy` manifest
  inside the app (which is already done and shipped in the build). Both must be
  consistent; they are — both say no tracking, no data collected.

## While you're in there — the other two URLs
- **Support URL** (required): `https://mshammas.github.io/iClean/support`
  Entered per version, under **Distribution → [your version] → App Review /
  Version Information → Support URL** (labels vary), or the version's
  "App Store" info page.
- **Marketing URL** (optional): can be left blank.
- Full listing text is in `AppStore/metadata.md`.
