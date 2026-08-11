# FashON

Photograph your clothes, find out how they work together, and see them worn.

Local-only: no accounts, no backend, no cloud project to set up. Everything
lives on the phone. Scoring runs on the user's own Gemini API key.

---

## Setup

This repo contains `lib/`, `pubspec.yaml`, and config. Platform folders
(`android/`, `ios/`) are generated, not committed, so generate them once:

```bash
# 1. Generate the native scaffolding in a temp dir
flutter create --org com.yourname --project-name fashon /tmp/fashon_scaffold

# 2. Copy the platform folders in
cp -r /tmp/fashon_scaffold/android ./
cp -r /tmp/fashon_scaffold/ios ./

# 3. Delete the scaffold's placeholder test, which references a `MyApp` class
#    this project does not have. The real test is test/scoring_test.dart.
rm -f test/widget_test.dart

# 4. Pull dependencies
flutter pub get
```

### One required native change

`flutter_secure_storage` uses encrypted shared preferences, which needs API 23
or higher. In `android/app/build.gradle.kts`:

```kotlin
defaultConfig {
    minSdk = 23
}
```

### Run it

```bash
flutter devices          # confirm the phone is attached
flutter run              # debug, hot reload
flutter build apk --release
```

On iOS, add `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription` to
`ios/Runner/Info.plist` or the picker crashes on first use. Android needs no
manifest permission — `image_picker` uses the system camera intent.

### First launch

The app opens on an empty closet. Add two garments, then go to Settings
(cog, top right of Closet) and paste a Gemini API key from
`aistudio.google.com/apikey`. Nothing scores without one.

---

## Sections

Four tabs, in the order of the work:

| Tab | Does |
|---|---|
| **Closet** | Every garment you have photographed, grouped head to toe. Camera or photo library. Tap for detail and its pairings, long-press to delete. |
| **Match** | Two modes. *Rate my pick* scores the garments you selected. *Find a piece* ranks every candidate in a category against your selection. |
| **Combos** | Every pairing ever judged, sorted and filtered. Pure cache — never calls the API. |
| **Looks** | Saved outfits with their score and rendered preview, filtered by tag. |

Camera capture, closet storage, per-user API key, cached pairwise scores shown
as combinations, upgrade suggestions, and Nano Banana previews are all here.

---

## How the scoring works

**Pairwise, then averaged.** Three selected garments is three pairs; a candidate
is ranked on the mean of its pairwise scores. Sending the whole outfit as one
prompt would be fewer calls, but pairs are what make the cache work: swapping
one garment only costs the pairs that actually changed, and every pair scored
anywhere in the app is reused everywhere else, forever.

**Cache-first, single door.** Everything goes through `PairScoringService`. It
checks SQLite, coalesces concurrent requests for the same pair into one call,
runs three at a time, and writes results back. The second time you ask the same
question, it costs nothing.

**Upgrade suggestions are free.** After rating a selection, the app searches the
cache for a garment that already scored higher than one you picked, and offers
the swap. Cache-only by design — it runs unprompted, so it must never spend.

**The backfill is what makes those suggestions fire.** Because they are
cache-only, they can only spot a better option if that pairing has already been
judged, so on a fresh closet they would stay silent for a long time.
`BackfillService` fills the gap in the background, and makes two choices worth
knowing:

- *Cross-category only.* Two tops are never worn together, so scoring that pair
  buys an answer nobody needs. Skipping same-category pairs cuts the work
  sharply — ten tops alone would otherwise add forty-five useless pairings — and
  leaves exactly the set the upgrade search reads.
- *The queue is derived, not stored.* Pending work is the difference between
  every useful pair and the keys already cached. Nothing to persist or keep in
  sync, and it is correct after a crash, a reinstall, or a rubric bump with no
  bookkeeping.

It runs one pairing at a time with a pause between, so foreground scoring always
feels faster. Runs are capped (default 40) rather than unbounded, a 429 moves it
to a resumable *throttled* state instead of failing, and the banner in Combos
always shows what it is doing with a one-tap stop. It is off until you turn it
on, and the first time asks plainly what it will cost — spending someone's quota
unattended needs consent once, not a buried default.

**Rubric versioning.** `GeminiService.promptVersion` is stamped on every stored
verdict. Edit the prompt, bump the constant, and old scores stop being served
rather than being silently mixed with new ones. Nothing needs deleting.

**Cancellation.** Changing your selection mid-run invalidates it through a run
token; the abandoned run discards its results instead of overwriting a selection
you have since changed. Pairs it finished stay cached.

### The prompt

Four weighted pillars carried over from the original: colour harmony 40%,
texture and material synergy 30%, silhouette and proportion 20%, style and
occasion cohesion 10%, with explicit calibration anchors to stop the model
drifting toward 7.

Output is five advice arrays and no garment description — you are looking at
the photos, so a description is filler. What earns points, what costs points,
what to change, plus shoes and accessories to complete it. Twelve words per
entry. The model is told never to comment on bodies or faces.

`gemini-3.6-flash` ignores `temperature`, `top_p` and `top_k` and errors on
penalty parameters, so `generationConfig` carries only
`response_mime_type: application/json`. Consistency comes from the prompt.

---

## Profile

`Profile` (person icon on Closet, or the top row of Settings) tells the app who
it is styling. The fields are split by consequence, and the split is the whole
design:

**Styling fields** — undertone, height band, build, usual occasions. Each maps
onto a scoring pillar, so they legitimately change what a good pairing is. They
form `UserProfile.fingerprint`, which is part of the cache key: change one and
cached scores become misses that have to be re-earned.

**Render fields** — name, photo, age, height in cm, weight, how you dress. These
only shape a generated preview, and previews are never cached, so editing them
is free.

That means correcting your weight or swapping your photo costs nothing, and only
a deliberate change to how you want to be styled ever spends money. A profile
with no styling fields fingerprints as `none` — identical to what pre-profile
rows carry — so filling in a name or a photo leaves an existing cache fully
valid. Height is asked for twice on purpose: a coarse band drives proportion
advice and is part of the fingerprint, while the exact figure is render-only, so
correcting yourself by a centimetre never triggers a rescore.

Changing a styling field deliberately does *not* kick off scoring, even with
background scoring on — re-judging a whole closet because someone tapped a chip
would be an expensive surprise. The pending count updates and the Combos banner
offers the work instead.

The photo is stored on the device and sent only when rendering a preview. Where
a stated age is under 18, previews render the garments without using it as a
likeness reference.

## Layout

```
lib/
  main.dart                    startup ordering, provider graph
  theme/app_theme.dart         palette, type scale, ThemeData
  models/
    clothing_item.dart         garment + GarmentCategory
    pair_score.dart            verdict + ScoredCandidate + pairKeyFor()
    outfit.dart                saved Look + LookTag
    user_profile.dart          wearer context + cache fingerprint
  data/
    database.dart              SQLite schema, indexes, cascades
    image_store.dart           on-disk photos, downscale on the way in
    app_settings.dart          key-value prefs (schema v2)
    profile_repository.dart    single-row profile (schema v3)
    item_repository.dart
    score_repository.dart      the cache
    look_repository.dart
  services/
    api_key_service.dart       platform keystore
    gemini_service.dart        REST, prompt, JSON extraction
    pair_scoring_service.dart  cache-first, concurrency, cancellation
    backfill_service.dart      background queue, capped and cancellable
  viewmodels/
    closet_viewmodel.dart
    match_viewmodel.dart
    combinations_viewmodel.dart
    looks_viewmodel.dart
    profile_viewmodel.dart
  views/
    root_screen.dart                    bottom nav, holds the four tabs
    closet/
      closet_screen.dart                Closet tab
      item_detail_screen.dart           one garment + its pairings
    match/
      match_screen.dart                 Match tab
    combinations/
      combinations_screen.dart          Combos tab
      pair_detail_screen.dart           full verdict for one pairing
    looks/
      looks_screen.dart                 Looks tab + LookDetailScreen
    profile/
      profile_screen.dart               wearer context + portrait
    settings/
      settings_screen.dart              API key, cache, models
    widgets/
      score_ring.dart                   ScoreRing, ScorePill
      garment_tile.dart                 GarmentTile, GarmentImage, SwatchPair
      backfill_banner.dart              background scoring status + controls
      common.dart                       Panel, EmptyState, AdviceList, FilterRow,
                                        SectionLabel, ErrorNotice, ScoringProgress

test/
  scoring_test.dart                     pairKeyFor, PairScore parsing, score bands
```

Every path above is a file in this repo already — nothing needs creating. The
folder is the tab: one directory per section, and a screen only ever lives in the
directory of the tab that opens it. `LookDetailScreen` is the one exception,
sharing a file with `looks_screen.dart` because it is small and nothing else
routes to it.

Anything reused by two or more tabs goes in `widgets/`, which is why the score
ring lives there rather than under `match/` — Match, Combos, and Looks all draw
it. If you add a widget and only one tab uses it, keep it in that tab's file
until a second caller appears.

Five tables, at schema version 3. `pair_scores` has indexes on both `item_a` and
`item_b`, so
finding everything one garment pairs with is an indexed lookup rather than a
table scan, and foreign keys cascade so deleting a garment takes its scores with
it — no window where a score points at something that no longer exists.

Photos are downscaled to 1024px once, on import, with EXIF orientation baked in.
The model does not need more to judge colour and drape, the grid shows 512px
thumbnails, and the expensive decode happens once per garment instead of once
per request.

---

## Security

The API key lives in the Android Keystore / iOS Keychain and nowhere else — not
in source, not in the database, not in shared preferences. An APK can be
unpacked in about a minute, so a key compiled into the binary is a published
key. Asking each user for their own means a leaked build can only bill the
person who built it.

`secrets.dart` and `*.env` are gitignored. Do not add a fallback key "just for
testing" — that is exactly how keys end up in git history.

---

## Design

Palette comes from a tailor's world rather than a UI kit: unlit dressing-room
plum for the ground, aged brass for anything actionable or numeric, eucalyptus
and clay for the two halves of a verdict. No pure black or white anywhere, so
photographed garments sit in the page rather than floating on it.

The signature element is the **score ring** — an arc that opens at the bottom
like a tape measure looped on itself, rather than a progress bar. A bar reads as
progress toward finishing a task; a score is a judgement. Pairings use a
**swatch pair** motif, two photos clipped and angled like fabric swatches, so it
is immediately obvious that the combination is the subject.

Type carries personality through tracking rather than a licensed face: display
sizes pull tight and negative, small labels open wide and uppercase like the
print on a garment tag. Add `google_fonts` later and only `theme/app_theme.dart`
changes.

---

## Known limits

- **HEIC** cannot be decoded by `package:image`. `image_picker` returns JPEG on
  both platforms, so normal capture is fine; files imported by other means will
  be stored as-is without downscaling.
- **Previews are single-shot.** Nano Banana 2's resolution options (0.5K–4K),
  aspect ratios, and conversational editing are not wired up yet — it renders at
  default 1K.
- **No cross-device sync.** Deliberate: it is what buys you zero-setup launch.
  The repository layer is the seam if you ever want to add a backend.
- **Thin test coverage.** `test/scoring_test.dart` covers the cache key, JSON
  parsing, the row round trip, and the score bands — the pure logic where a bug
  is silent rather than visible. The viewmodels and widgets are untested; the
  scoring coordinator's concurrency and cancellation are the next thing worth
  covering.
