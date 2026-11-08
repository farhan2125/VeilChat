# VeilChat — Design Overhaul, Glitch Cleanup & Feature Expansion

> Deliverable notes for the branding, UI/UX, group-management and refactoring pass.
> Everything below is already implemented in the repo — this file is the map.

---

## 1. Branding & Logo System

### Concept
**"The Veil"** — a shield/veil silhouette folded into a speech bubble, with an
encrypted lock-node at its core. Reads as *privacy*, *stealth* and *conversation*
in one mark. Works at 16 px (notification) and 1024 px (store icon).

### Palette (`lib/branding/veil_brand.dart`)

| Token | Hex | Use |
|---|---|---|
| `veilVoid` | `#05070D` | App background (deep space black) |
| `veilInk` | `#0D1117` | Surfaces / cards |
| `veilTeal` | `#00E5C0` | Primary neon accent (cyber emerald-teal) |
| `veilIndigo` | `#6C5CE7` | Secondary ambient indigo |
| `veilViolet` | `#A855F7` | Gradient tail |
| `veilSignal` | `#00FF88` | Online / success |
| `veilAlert` | `#FF4D6D` | Destructive (kick, leave, delete) |

Gradients: `VeilBrand.primaryGradient` (teal → indigo), `VeilBrand.auroraGradient`
(teal → violet → indigo) for hero headers and the logo fill.

### Assets

```
assets/branding/
├── veilchat_icon.svg      # 1024×1024 launcher mark (shield + bubble + lock node)
├── veilchat_logo.svg      # stacked lockup (mark + "VeilChat")
└── veilchat_wordmark.svg  # horizontal wordmark for app bars / splash
```

### Code-drawn logo (no asset dependency)

`lib/branding/veil_logo.dart` renders the identical mark with `CustomPainter`, so
splash/loading states never wait on asset decode:

```dart
const VeilLogo(size: 96)                       // mark only
const VeilLogo(size: 96, showWordmark: true)   // full lockup
const VeilLogoAnimated(size: 120)              // breathing glow + orbit ring
```

---

## 2. UI/UX Glitch & Layout Fixes

### 2.1 Call History header (the reported clipping bug)

**Root cause:** the screen used a plain `Column` inside `Scaffold` with a manual
top padding while `extendBodyBehindAppBar` was on. The title + filter chips were
painted underneath the status bar with a second opaque background behind them,
producing the overlapping artifacts.

**Fix (`lib/call_history_screen.dart`):**

```
NestedScrollView
└── headerSliverBuilder
    └── SliverOverlapAbsorber
        └── SliverAppBar
            ├── pinned: true          ← header never clips or disappears
            ├── floating: false
            ├── expandedHeight: 148
            ├── flexibleSpace: FlexibleSpaceBar(
            │     background: BackdropFilter(blur 24) + aurora gradient)
            └── bottom: PreferredSize(56)  ← filter chips live *inside* the app bar
body
└── SliverOverlapInjector + CustomScrollView (list scrolls cleanly under header)
```

Key details:
- `MediaQuery.of(context).padding.top` is respected by the `SliverAppBar`
  automatically — no more manual `SafeArea` double-padding.
- The blur backdrop is `ClipRect`-wrapped so the filter cannot bleed outside the
  header bounds (this was the "background artifact").
- Chips are a `ListView(scrollDirection: Axis.horizontal)` → **no RenderFlex
  overflow** on narrow devices.
- `systemOverlayStyle` is set so status-bar icons stay legible over the gradient.

### 2.2 General polish

- Every `Row`/`Column` that renders user-supplied text now uses
  `Expanded` + `maxLines` + `TextOverflow.ellipsis` (kills RenderFlex overflow
  warnings on small/wide ratios).
- Standardised spacing scale: `4 / 8 / 12 / 16 / 20 / 24`.
- Cards: `radius 18–24`, soft shadow `blur 18, alpha .08`, 1 px hairline border
  at `alpha .10` for dark-mode contrast (WCAG AA on body copy).
- Micro-animations: `AnimatedContainer` on chip/tab selection (200 ms `easeOut`),
  `Hero` on group + call avatars, spring-scale on primary buttons.
- Haptics unified in `lib/veil_feedback.dart`:
  `VeilFeedback.tap()`, `.select()`, `.success()`, `.warn()`, `.error()`.

---

## 3. Group Chat & Group Info Overhaul

### 3.1 New screen — `lib/group_info_screen.dart`

```
┌─────────────────────────────────────────┐
│  ◀   [ glassmorphic hero header ]    ⋮  │  ← SliverAppBar, pinned, blur 24
│        ╭───────────────╮                │
│        │  Group Avatar │  (Hero)        │
│        ╰───────────────╯                │
│         GROUP NAME                      │
│    ● 12 members · 4 online              │
│    🔒 End-to-end encrypted  [verified]  │  ← Encryption Status Indicator
├─────────────────────────────────────────┤
│  📌 Pinned message banner (dismissible) │
├─────────────────────────────────────────┤
│  [ Media ] [ Search ] [ Mute ] [ Wall ] │  ← quick-action tiles
├─────────────────────────────────────────┤
│  MEMBERS (avatar stack + list)          │
│   ▸ haiz        [Owner]      ● online   │
│   ▸ pinki       [Admin]      ○ offline  │
│   ▸ ali                      ● online   │  → tap = admin action sheet
├─────────────────────────────────────────┤
│  Export Chat · Encryption Status        │
│  ⚠  Leave Group                         │
└─────────────────────────────────────────┘
```

### 3.2 Expanded options menu

| Feature | Behaviour |
|---|---|
| **Group Media / Docs Gallery** | Tabbed grid (Media / Docs / Links) built from `group_messages` where `type IN ('IMAGE','FILE')`. |
| **Mute Notifications** | Duration picker — 8 hours / 1 week / Always. Stored as `mutedUntil` epoch-ms, auto-expires via `GroupService.isMutedNow()`. |
| **Export Chat** | Streams the conversation to a `.txt` in the documents dir and hands it to `share_plus`. |
| **Search in Group** | Bottom sheet with live filtering over the in-memory message list (never blocks the raster thread). |
| **Custom Group Wallpaper** | Per-group key persisted in the `wallpaper` column; falls back to the global wallpaper. |
| **Encryption Status Indicator** | Shows cipher suite (XChaCha20-Poly1305 / X25519) + key fingerprint chip. |

### 3.3 Admin controls — now actually work

`lib/services/group_service.dart` gained real, reactive implementations:

```dart
Future<bool> addMember(String groupId, String username);
Future<bool> removeMember(String groupId, String username);   // Kick
Future<bool> promoteToAdmin(String groupId, String username);
Future<bool> demoteAdmin(String groupId, String username);
Future<bool> setMuted(String groupId, DateTime? until);
Future<bool> leaveGroup(String groupId);
bool        isAdmin(Group g, String user);
bool        isMutedNow(Group g);
```

Each one follows the same contract:

1. **Permission check** (owner/admin) — silently refuses otherwise.
2. **Optimistic local mutation** — the member vanishes from the list *instantly*.
3. **`_emit(group)`** pushes to `groupUpdateStream` + `groupsStream`, so the
   info screen, chat header and chat list all rebuild in the same frame.
4. **Persist** to SQLite.
5. **Rollback** the optimistic change if the socket send throws.
6. Returns `bool` → caller shows a success/error `SnackBar`.

`GroupChatDetailScreen` subscribes to `groupUpdateStream` and refreshes
`_members` live, so a kick performed from the info screen is reflected in the
conversation header immediately.

### 3.4 Confirmation modals + feedback

Every destructive/elevated action (Kick, Promote, Demote, Leave, Delete) routes
through a themed `AlertDialog` with:
- explicit consequence copy ("`ali` will no longer receive messages…"),
- a red/amber tinted confirm button,
- `VeilFeedback.warn()` haptic on open and `.success()` / `.error()` on result,
- a floating `SnackBar` reporting the outcome.

---

## 4. Terminal Log Analysis → Fixes Applied

| Log line | Diagnosis | Fix |
|---|---|---|
| `E/SQLiteLog: duplicate column name: isHidden / hiddenKey / isPinned / …` | `ALTER TABLE` migrations re-ran on every `onOpen`, each throwing a native SQLite error. | `DatabaseService` now reads `PRAGMA table_info(...)` once, caches the column set, and only issues `ALTER TABLE` for genuinely missing columns. New columns (`admins`, `mutedUntil`, `wallpaper`, `pinnedMessage`) use the same guarded path. |
| `I/Choreographer: Skipped 79/77/94 frames!` | Group + DB loading ran on the platform thread during first frame. | `loadGroups()` is de-duplicated per user (`_loadedForUser` guard), heavy decode work is `await`-ed off the build phase, and list decode uses lazy builders. |
| `❌ Decrypt: SecretBoxAuthenticationError … wrong MAC` | Unhandled decrypt failures spamming the console; UI showed raw hex. | Decrypt paths are wrapped in `try/catch`; failures render a `🔒 Decryption failed` placeholder instead of leaking ciphertext, and are logged once (not per frame). |
| `📞 Sent ICE to pinki` ×20 after `Sent END` | ICE candidates kept flowing after hang-up → listener leak. | Call/WebRTC subscriptions are cancelled in `dispose()`; ICE emission is gated on connection state. |
| `W/FlutterJNI: Tried to send a platform message … FlutterJNI was detached` | Streams emitting after the engine detached (hot restart / logout). | All controllers are `isClosed`-checked before `add()`; every `StreamSubscription` is stored and cancelled in `dispose()`. |
| `modalSub` re-subscribed inside `StatefulBuilder` | New subscription created on every rebuild of the recording sheet → leak. | Guarded with `modalSub ??= …` and cancelled on both stop and cancel paths. |
| `group!.unreadCount` force-unwrap | Potential null-safety crash inside `_handleGroupMessage`. | Replaced with the already null-checked local `group` reference. |

### Error-handling pattern now used everywhere

```dart
Future<void> _guard(String label, Future<void> Function() action) async {
  try {
    await action();
  } catch (e, st) {
    debugPrint('❌ $label failed: $e\n$st');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label failed'), backgroundColor: VeilBrand.veilAlert),
      );
    }
  }
}
```

---

## 5. pubspec / setup

No **new** runtime dependency is strictly required — the logo is code-drawn and
the SVGs are optional design sources.

Add the branding folder to assets (already done):

```yaml
flutter:
  assets:
    - assets/images/
    - assets/branding/
```

Optional extras:

```yaml
dependencies:
  flutter_svg: ^2.0.10          # only if you want to render the .svg files directly

dev_dependencies:
  flutter_launcher_icons: ^0.13.1

flutter_launcher_icons:
  android: true
  ios: true
  image_path: "assets/branding/veilchat_icon.png"   # export the SVG at 1024×1024
  adaptive_icon_background: "#05070D"
  adaptive_icon_foreground: "assets/branding/veilchat_icon.png"
```

Then:

```bash
flutter pub get
dart run flutter_launcher_icons        # only if you added the package
flutter run
```

---

## 6. Verification

```bash
flutter analyze
```

→ **0 errors.** Remaining items are info-level lints (`withOpacity` deprecation
and `unnecessary_underscores`) that are cosmetic and safe to migrate later with
`dart fix --apply`.

---

## 7. File map of this change set

```
assets/branding/veilchat_icon.svg        (new)
assets/branding/veilchat_logo.svg        (new)
assets/branding/veilchat_wordmark.svg    (new)
lib/branding/veil_brand.dart             (new)  palette, gradients, shadows, spacing
lib/branding/veil_logo.dart              (new)  CustomPainter logo + animated variant
lib/veil_feedback.dart                   (new)  haptics + themed snackbars
lib/group_info_screen.dart               (new)  premium group info & management
lib/call_history_screen.dart             (rewritten)  SliverAppBar header fix
lib/services/group_service.dart          (refactor)   admin controls, mute, rollback
lib/services/database_service.dart       (refactor)   guarded migrations, new columns
lib/services/wallpaper_service.dart      (refactor)   per-group wallpaper support
lib/group_chat_detail_screen.dart        (refactor)   opens GroupInfoScreen, in-chat search
pubspec.yaml                             (assets)
```
