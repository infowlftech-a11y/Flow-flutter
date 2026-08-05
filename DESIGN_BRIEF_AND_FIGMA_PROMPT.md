# FLOW 3.0 — Design Brief & AI Generation Prompt

> **Source of truth.** Every colour, font size, radius, duration and screen in this
> document was read out of the shipping Flutter codebase (`lib/core/theme/`,
> `lib/router.dart`, `lib/features/**`), not invented. Where a value is a
> recommendation rather than a current fact, it is marked **[NEW]**.

> **One correction to the request.** The brief template asked for screens like
> *"Prompt Input"* and *"AI Studio Output View."* Flow has none — it is a
> two-sided kitesurfing lesson marketplace, not an AI tool. That part of the
> template appears to be boilerplate from another project, so the inventory
> below covers Flow's **actual 28 screens**. Nothing has been padded to match
> the example list.

---

## 1. Product context — read this before designing anything

**Flow** connects riders with certified kitesurfing trainers on the Egyptian Red
Sea coast. Riders find a trainer, book hours on the water, and check in on the
beach with a QR ticket. Trainers run their entire working day from a Command
Center.

### The two-sided constraint that drives every layout decision

One app serves two people whose needs barely overlap:

| | **Rider** (`kiter`) | **Trainer** (`business`) |
|---|---|---|
| Goal | Find someone, book an hour, show up | Fill the calendar, approve requests, get paid |
| Home tab | **Explore** — browse & filter trainers | **Command Center** — today's manifest, approvals, earnings |
| Core loop | Browse → pick day/hours → request → QR check-in | Approve/decline → scan rider in → finish session |
| Session count | A handful | Dozens per week |

The bottom navigation is **the same four slots for both roles**, but slot 1
resolves to a different screen depending on role. Trainers are *never* routed to
the rider Sessions branch. Design both sides as one product, not two skins.

### The physical context — this is not a desk app

Design for **one hand, in direct Red Sea sunlight, with wet or sandy fingers,
on a beach, possibly on 3G.** Consequences that are non-negotiable:

- Touch targets ≥ 48×48 dp, generously spaced. No dense toolbars.
- High contrast even in the dark theme — this app is used outdoors at midday.
- Every network surface needs a real loading, empty, and error state.
- Money and time must never be ambiguous.

### Roles in the system

`kiter` (rider) · `business` (trainer) · `admin` / `owner` / `support` (staff).
Riders self-activate on signup. **Trainers land `pending` and stay invisible in
Explore until staff approve them.** Suspended accounts (`blocked`) are held on a
gate screen until the ban lapses.

---

## 2. Brand identity

### 2.1 Origin

The palette is sampled from `assets/brand/logo.png` — three colours only:

| Role | HEX | Name |
|---|---|---|
| Logo background | `#020F2B` | **Ink navy** |
| Logo swoosh | `#1DB0FE` | **Azure** |
| Wordmark | `#FFFFFF` | **White** |

**Everything else in the system is a tint or shade of those three.** Keep that
discipline — do not introduce a fourth hue for decoration.

### 2.2 Full colour ramps

**Navy ramp** — dark-theme surfaces, light-theme text

| Token | HEX |
|---|---|
| `navy950` | `#020A1E` |
| `navy900` | `#041530` |
| `navy850` | `#071C3E` |
| `navy800` | `#0B2449` |
| `navy700` | `#143158` |
| `navy600` | `#1F4270` |

**Azure ramp**

| Token | HEX | Use |
|---|---|---|
| `azure` | `#1DB0FE` | Brand accent, always vivid, **both themes** |
| `azureDeep` | `#0077C9` | Light-theme primary (AA on white) |
| `azureDim` | `#0E5E9C` | Pressed / muted |
| `azureGlow` | `#63C8FF` | Dark-theme secondary, glows |
| `azurePale` | `#E1F2FF` | Light tint fills |

**Text on dark**: `mist #EFF5FF` · `haze #A6BAD8` · `slate #647CA5`
**Text on light**: `inkText #0A1B36` · `inkSub #48597B` · `inkFaint #8393B0`

**Semantic accents** (each has a deep variant for light theme)

| Meaning | Dark | Light | Tint (dark / light) |
|---|---|---|---|
| Success / confirmed | `#17CE92` | `#0B9A6C` | `#2617CE92` / `#1A0B9A6C` |
| Warning / pending | `#FFB547` | `#B97710` | `#26FFB547` / `#21FFB547` |
| Danger / cancelled | `#FF5D72` | `#D23B50` | `#26FF5D72` / `#1AD23B50` |

### 2.3 Theme definitions

Both themes are **fully designed — no inversion tricks.** Dark is the
brand-native look.

**DARK (default, brand-native)**

```
primary            #1DB0FE      onPrimary          #020F2B
secondary          #63C8FF      onSecondary        #020F2B
surface            #020A1E      onSurface          #EFF5FF
onSurfaceVariant   #A6BAD8
surfaceContainerLow/-Container      #041530
surfaceContainerHigh                #071C3E
surfaceContainerHighest             #0B2449
error              #FF5D72      onError            #020F2B
outline            #4D355C8F    outlineVariant     #33355C8F
card #041530 · cardHigh #071C3E · hairline #33355C8F · textFaint #647CA5
heroGradient       135°  #0A2C55 → #041530
```

**LIGHT (cool off-white, never pure white page)**

```
primary            #0077C9      onPrimary          #FFFFFF
secondary          #1DB0FE      onSecondary        #020F2B
surface            #F3F6FB      onSurface          #0A1B36
onSurfaceVariant   #48597B
surfaceContainerLow/-Container/-High  #FFFFFF
surfaceContainerHighest               #E9F0F9
error              #D23B50      onError            #FFFFFF
outline            #330A1B36    outlineVariant     #1F0A1B36
card #FFFFFF · cardHigh #FFFFFF · hairline #1F0A1B36 · textFaint #8393B0
heroGradient       135°  #020F2B → #0A2C55
```

Note the asymmetry that matters: **the hero gradient stays dark in *both*
themes.** Hero surfaces are always ink navy with white text — that is the
brand signature and it must not flip.

### 2.4 Visual style verdict

**Flat, confident minimalism with soft depth — not glassmorphism, not neumorphism.**

- Surfaces are **solid fills with hairline borders**, separated by elevation of
  colour (navy900 → navy850 → navy800), not by drop shadows.
- Azure is used **sparingly and only for meaning**: the active state, the
  primary action, the selected value. It is never decorative.
- No blur, no frosted panels, no gradient text, no glow except `azureGlow` on
  genuinely elevated brand moments.
- Generous negative space. The beach is chaotic; the app should not be.

---

## 3. Typography

Two variable fonts, weight driven through the `wght` axis.

- **Sora** — display / headings. Tight, confident, slightly condensed feel.
- **Inter** — all UI and body text.
- **Tabular numerals are mandatory** for money, counters, timers and hour
  ranges, so digits never jitter as values change.

### Exact type scale (in production)

| Token | Font | Size | Weight | Tracking | Line-height |
|---|---|---|---|---|---|
| displayLarge | Sora | 40 | 780 | −1.2 | 1.05 |
| displayMedium | Sora | 32 | 760 | −0.8 | 1.10 |
| displaySmall | Sora | 26 | 740 | −0.6 | 1.12 |
| headlineMedium | Sora | 22 | 700 | −0.4 | 1.15 |
| headlineSmall | Sora | 19 | 680 | −0.3 | 1.20 |
| titleLarge | Sora | 17 | 660 | −0.2 | 1.25 |
| titleMedium | Inter | 15.5 | 640 | −0.1 | 1.30 |
| titleSmall | Inter | 13.5 | 620 | — | 1.30 |
| bodyLarge | Inter | 15.5 | 440 | — | 1.45 |
| bodyMedium | Inter | 14 | 440 | — | 1.45 |
| bodySmall | Inter | 12.5 | 440 | — | 1.40 |
| labelLarge | Inter | 14.5 | 640 | +0.1 | — |
| labelMedium | Inter | 12.5 | 620 | +0.3 | — |
| **microLabel** | Inter | 11 | 700 | **+1.1** | — |

**microLabel is a signature element**: uppercase, letterspaced, `textFaint`
colour. It labels every form field, section header and pill. Use it liberally —
it is what makes the UI read as engineered rather than generic.

**Accessibility:** text scaling is clamped app-wide to **0.9×–1.3×** so dense
uppercase labels cannot overflow their pills. Design at 1.0× but verify 1.3×.

---

## 4. Shape, depth & motion

### Radii (exact, in use)

| Value | Applied to |
|---|---|
| **14** | The workhorse — buttons, cards, inputs, pickers, list tiles |
| 12 | Chips, small pills, banners |
| 8 | Tight inner elements |
| 20 | Dialogs |
| 24 | Large feature cards, FAB |
| **28** | Bottom sheets (top corners only) |
| 2 | Progress bars, sheet drag handle |

Default to **14**. It is the app's shape fingerprint.

### Depth

Colour-based elevation, not shadow. `card` → `cardHigh` → hairline border.
Hairlines are `#33355C8F` on dark, `#1F0A1B36` on light.

### Motion — functional only, 150–320 ms

| Duration | Use |
|---|---|
| 150 ms | Instant feedback, taps |
| **200 ms** | The default — error reveals, size changes |
| 220–260 ms | Content transitions, tag animation |
| 280–350 ms | Page/scroll transitions, scroll-into-view |
| 400 ms | Deliberate emphasis only |

Standard curve: **`easeOutCubic`**. Nothing bounces. Nothing decorates.

### Haptics vocabulary

`select` (tap/choice) · `light` (message sent) · `medium` (success) ·
`heavy` (destructive confirm) · `error` (validation failure).

---

## 5. Component inventory (existing, reusable)

| Component | Purpose |
|---|---|
| `AsyncView` | **Load-bearing.** Wraps every async surface; a retry is *structurally required*, so error dead-ends cannot ship |
| `SkeletonPulse` / `SkeletonCard` / `SkeletonList` | Loading. Never a spinner on content |
| `EmptyView` / `ErrorView` | Icon + title + body + action |
| `PrimaryButton` | Filled CTA with built-in busy state |
| `FlowPickerField` | Tap-to-open field; single value or removable tags |
| `showFlowPicker` | Searchable select sheet, single/multi, optional custom add |
| `showFlowSheet` | Standard modal: drag handle, title, subtitle, keyboard avoidance |
| `showFlowToast` | Snackbar with optional UNDO |
| `confirmAction` | Destructive confirmation dialog |
| `FlowChoiceChip` · `TagPill` · `SectionHeader` · `InfoTile` · `Stars` · `MicroAction` | Atoms |
| `FlowAvatar` · `FlowImage` | Images with placeholder + error fallback |
| `FlowLogo` · `FlowWordmark` · `WaveBackdrop` | Brand |

**`WaveBackdrop`** is the branded backdrop (ink navy with a wave silhouette)
used on splash, auth and gate screens.

---

## 6. Complete screen inventory & architecture

**28 screens.** Grouped by flow.

### 6.1 Entry & authentication (6)

**`/` Splash** — `WaveBackdrop`, centred `FlowLogo` + `FlowWordmark`. Holds
while auth and profile streams resolve. No spinner text.

**`/auth` Welcome** — Logo, wordmark, one-line value proposition. Two
full-width stacked actions: **Create an account** (filled) / *I already have an
account* (outlined). Fine print at the base. No back.

**`/auth/sign-in`** — Title *"Welcome back"* + subtitle. Email, Password (with
reveal toggle). Right-aligned *Forgot password?*. Filled **Sign in**. Footer:
*New to FLOW? Create an account*. On unknown email → azure **recovery card**
offering Sign up.

**`/auth/sign-up`** — *"Create your account"*. Name, Email, Password + reveal.
Animated **strength meter** (weak/fair/strong → coral/amber/emerald). Filled
**Create account**. Footer: *Already have an account? Sign in*. On taken email →
recovery card offering Sign in. **No confirm-password field** — the reveal
toggle replaces it.

**`/auth/reset`** — Single email field, **Send reset link**. Success is a
distinct state: large azure `mark_email_read` medallion, *"Check your inbox"*,
*"If an account exists for x@y…"* (deliberately identical whether or not the
account exists), plus **Back to sign in** and *Send it again*.

**Setup required** (non-route) — shown when Firebase config is missing. Plain,
technical, no branding.

### 6.2 Onboarding (3)

**`/onboarding/role`** — *"Who are you on the beach?"* Two large tappable
cards: **I'm a Kiter** (icon, description, "RIDE WITH FLOW") and **I'm a
Trainer** ("WORK WITH FLOW" + a shield note that trainer accounts are
reviewed). Sign out lives in the app-bar **trailing** slot, never the back slot.

**`/onboarding/rider`** — Single page. Circular `AvatarPicker` (tap → source
sheet → cropper). Then: Full name · **Nationality picker** + Age (3:2 row) ·
Kite level picker · Home spot picker · **Languages** (multi-select tags) ·
**Quiver** (multi-select tags) · Short bio (counter). CTA **"Let's ride."**
Failed validation scrolls the first unmet field into view.

**`/onboarding/trainer`** — **4-step wizard** with a segmented progress bar.
Step 1 Profile (photo, name, bio, languages, gallery) · Step 2 Spot (kite spot
picker, Maps link) · Step 3 Rate (€60–110, live preview) · Step 4 Verification
(IKO ID, certificate upload). Back/Continue pair at the base; system back steps
*through* the wizard and only then exits.

### 6.3 Gates (3)

All use `WaveBackdrop` + a large status medallion. Never a dead end — each
offers an action.

**`/pending`** — Amber. "Application under review." Sign out available.
**`/blocked`** — Coral. Countdown to expiry (ticks every minute), plus the
**appeal** flow: reason, evidence attachments, threaded replies from staff.
**`/rejected`** — Coral. Reason + note, and a route to **Support** so a
declined trainer can reach a human.

### 6.4 Main shell — 4 bottom-nav slots

Slot 1 is role-dependent. Labels: **Explore/Home · Sessions · Inbox · Profile**.

#### `/home` — RIDER: Explore
Search field · horizontal spot filter chips · sort control · list of
**trainer cards** (avatar, name, spot, rating stars, hourly rate, languages,
favourite toggle). Skeleton list while loading; empty state when filters match
nothing. Pull to refresh.

#### `/home` — TRAINER: Command Center
Tabbed. **Today**: date header, stat tiles on the hero gradient (today's
sessions / hours / earnings), pending **request cards** with Approve/Decline,
"Coming up" list, and a prominent **Scan rider in** action. **Schedule tab**:
day strip, hour-by-hour timeline 08:00–18:00 showing free/booked/blocked, plus
**Add walk-in** and **Schedule time off** sheets, and a vacation list.

#### `/sessions` — Rider only
Three buckets: **Upcoming / Active / History**. Booking cards carry a status
pill (Pending amber · Confirmed emerald · Active azure · Completed · Cancelled
coral), date, hour range, trainer, price. Actions: **Show QR ticket**, Cancel,
Rate. Supports `?highlight=<id>` deep link from a push tap — the target card
pulses.

#### `/inbox`
Thread list: avatar, name, last-message preview, relative time, unread badge.
Empty state when no conversations.

#### `/profile`
Grouped settings cards: Personal details · Notifications · Help & support ·
**Appearance** (Auto/Light/Dark segmented) · Security & data · Sign out ·
**Danger zone** — Delete my account (coral). Version label at the base. Staff
see an extra **Admin console** row.

### 6.5 Detail & task screens (10)

**`/trainer/:id`** — Gallery header (page dots, tap → full-screen viewer) ·
name, spot, rating · rate · bio · languages · reviews (with own-review delete) ·
**Report** action. Sticky bottom **Book** bar.

**`/station/:id`** — Station variant: instructors list, services, and
**safari trips** (seats left, departure date, price per seat).

**`/book/:id`** — Provider card · **day strip** (21 days) · **hour grid
08:00–17:00** with free/booked/too-soon/blocked states and reasons · contiguous
selection only · live summary card (hours × rate) · message field · gear toggle
· sticky total bar → **Review & confirm** sheet → success dialog.

**`/chat/:id`** — Message bubbles (own = azure, theirs = card), day dividers,
timestamps every 10 min gap, jump-to-latest pill with unread count, input bar.

**`/notifications`** — Grouped list, unread emphasis, swipe to delete,
**Mark all read** with UNDO.

**`/support`** — Ticket list + threaded ticket view.

**`/admin`** — Staff only. **Approvals queue** (trainer applications → Accept /
Reject with note), **Reports** (uphold & suspend / dismiss), **Appeals**
(threaded, lift suspension). Badge counts on each section.

**`/profile/edit`** — Avatar, name, phone, nationality picker, age, level,
languages, bio, gallery manager. Read-only Email and Training spot with
explanatory helper text. Save enabled only when dirty.

**QR scanner** (non-route) — Full-bleed camera, dark scrim with a clear cutout,
corner brackets, instruction line, error banner for a refused ticket, and a
graceful camera-permission state.

**Crop screen** (non-route) — Ink background, fixed mask (circle for avatars,
4:3 for gallery/certificates), photo moves underneath, azure rim,
rule-of-thirds guides, *"Pinch to zoom · drag to reposition."* Cancel / Done.

**QR ticket dialog** — The rider's check-in ticket: large QR, trainer, date,
hour range, and a state flip once scanned.

---

## 7. UX & interaction specifications

### 7.1 The four states — every async surface has all four

1. **Loading** — skeleton shapes matching the real content's geometry.
   *Never a bare spinner over content, and never default to "free"/"empty"
   before data arrives — loading must not lie.*
2. **Empty** — icon, headline, one line of explanation, and an action.
3. **Error** — icon, plain-language cause, **and a retry that always works.**
4. **Loaded**.

### 7.2 Micro-interactions worth designing

- **Booking grid pruning** — if someone takes an hour you had selected, it is
  removed live and a toast explains why. If the removal splits your run, the
  hours after the gap drop too (sessions must be back-to-back).
- **Optimistic approve/decline** with busy guards — buttons cannot double-fire.
- **Mark-all-read UNDO** — toast with an UNDO affordance.
- **Push tap → deep link** to the exact booking, which then pulses.
- **Live countdown** on the blocked gate, ticking each minute.
- **Strength meter** animating between weak/fair/strong.
- **Tag add/remove** animating in the picker field.
- **Success dialog** after booking — not dismissible by tapping outside; one
  Done button.

### 7.3 Form conventions

- Label = `microLabel` uppercase above the field; required marked with an azure `*`.
- Errors appear **inline beneath the field**, never in an alert.
- Validation stays quiet until the first submit attempt, then goes live.
- On failed submit, focus and scroll jump to the first unmet field.
- Form-level problems (offline, rate-limited) go in a **banner** at the top;
  anything tied to one input goes under that input.
- Long/large option sets use the **searchable picker sheet**, never a wall of chips.

### 7.4 Content rules that affect layout

- Money: `€120` whole, `€72.50` fractional, tabular figures, `—` when unknown.
- Dates: `Fri 14 Aug`, long form `Friday, 14 August`, `--` fallback.
- Relative time: `now`, `4m`, `2h`, `3d`, then `12 Mar`.
- Hours are whole and shown as ranges: `09:00–11:00`.
- **Unrated trainers display 5.0** (deliberate product rule).

---

## 8. What to keep vs. what to fix in the redesign

**Keep** — the three-colour brand discipline, Sora+Inter pairing, microLabel
treatment, the 14 dp shape language, colour-based elevation, the structurally
enforced retry, and the four-state discipline.

**Fix / improve**

- Visual hierarchy on the **Command Center** — it carries the most information
  density in the app and needs the clearest structure.
- The **booking hour grid** deserves a stronger, more legible state design
  (free / booked / too-soon / blocked all need to be distinguishable at a
  glance in sunlight).
- **Explore trainer cards** need a stronger scanning rhythm.
- Sessions status pills could carry more meaning at a glance.
- Empty states are functional but visually plain — a real opportunity.

---

## 9. MASTER PROMPT — paste into Stitch / v0 / Figma AI

```
Design a complete, production-ready mobile UI kit for "FLOW" — a two-sided
kitesurfing lesson marketplace for the Egyptian Red Sea coast. Riders book
certified trainers by the hour and check in on the beach with a QR ticket;
trainers run their whole working day from a Command Center. Android-first,
portrait only, one-handed use in bright outdoor sunlight.

BRAND
Three colours only, sampled from the logo: ink navy #020F2B, azure #1DB0FE,
white #FFFFFF. Everything else is a tint or shade of these. Do not add a
fourth hue.

STYLE
Flat, confident minimalism with soft depth. NOT glassmorphism, NOT neumorphism,
no blur, no frosted panels, no gradient text. Surfaces are solid fills with
1px hairline borders; elevation is expressed by colour steps, not drop shadows.
Azure is used sparingly and only for meaning — active state, primary action,
selected value — never decoration. Generous negative space.

DARK THEME (default, brand-native)
bg #020A1E · card #041530 · card-elevated #071C3E · card-highest #0B2449
hairline #33355C8F · primary #1DB0FE · secondary #63C8FF
text #EFF5FF · text-secondary #A6BAD8 · text-faint #647CA5
success #17CE92 · warning #FFB547 · danger #FF5D72 (tints at 15% alpha)

LIGHT THEME (fully designed, not inverted)
bg #F3F6FB · card #FFFFFF · card-highest #E9F0F9 · hairline #1F0A1B36
primary #0077C9 · secondary #1DB0FE
text #0A1B36 · text-secondary #48597B · text-faint #8393B0
success #0B9A6C · warning #B97710 · danger #D23B50
Hero/feature surfaces stay DARK ink-navy with white text in BOTH themes —
gradient 135° #0A2C55 → #041530. This is the brand signature.

TYPOGRAPHY
Sora for headings, Inter for UI and body. Tabular numerals for all money,
counters and time ranges.
Display 40/32/26 Sora weight 780-740, tight tracking (-1.2 to -0.6).
Headings 22/19/17 Sora 700-660. Titles 15.5/13.5 Inter 640-620.
Body 15.5/14/12.5 Inter 440, line-height 1.45.
SIGNATURE ELEMENT: "microLabel" — 11px Inter weight 700, UPPERCASE,
letterspacing +1.1, in the faint text colour. Use it for every form field
label, section header and pill. It is what makes the UI read as engineered.

SHAPE & MOTION
Corner radius 14 is the default for buttons, cards, inputs and list tiles.
12 for chips and banners, 20 dialogs, 24 large feature cards, 28 bottom-sheet
top corners. Motion is functional only, 150–320ms, easeOutCubic. Nothing
bounces or decorates. Touch targets ≥48dp.

SCREENS TO DESIGN (both themes)
Auth: Splash · Welcome (two stacked CTAs) · Sign in · Create account with
animated password-strength meter · Reset password + "check your inbox" success.
Onboarding: role chooser (two large cards: Kiter / Trainer) · one-page rider
form · four-step trainer wizard with segmented progress.
Gates: Pending review (amber) · Suspended with live countdown + appeal thread
(coral) · Rejected (coral). All use a branded wave backdrop and a large status
medallion.
Rider: Explore (search, spot filter chips, sort, trainer cards with avatar,
rating, hourly rate, languages, favourite) · Trainer profile (gallery header,
reviews, sticky Book bar) · Booking screen (21-day strip, hour grid 08:00–17:00
with free/booked/too-soon/blocked states, live price summary, sticky total bar)
· Review & confirm sheet · Booking success dialog · Sessions in three buckets
(Upcoming/Active/History) with status pills · QR ticket dialog.
Trainer: Command Center Today tab (stat tiles on the dark hero gradient,
pending request cards with Approve/Decline, today's manifest, Scan rider in) ·
Schedule tab (day strip, 08:00–18:00 timeline, add walk-in, schedule time off)
· QR scanner (full-bleed camera, dark scrim, clear cutout with corner brackets).
Shared: Inbox thread list · Chat (own bubbles azure, day dividers, jump-to-
latest pill) · Notifications with swipe-delete and mark-all-read UNDO ·
Profile settings with Auto/Light/Dark segmented control and a coral danger zone
· Edit profile · Admin console (approvals queue, reports, appeals) · Support
tickets · Image cropper (fixed circular or 4:3 mask, photo moves underneath,
azure rim, rule-of-thirds guides).

COMPONENTS TO DELIVER
Buttons (filled/outlined/text/icon, each with a busy state) · text input with
uppercase microLabel, inline error and password reveal · searchable select
sheet with removable tags · choice chips · status pills (pending/confirmed/
active/completed/cancelled) · trainer card · booking card · stat tile on hero
gradient · avatar with fallback · rating stars · bottom sheet with drag handle
· confirmation dialog · toast with UNDO · bottom nav (4 slots) · segmented
control · day strip · hour-slot grid cell in all four states · skeleton
loaders · empty state · error state with retry.

MANDATORY UX RULES
1. Every async surface needs FOUR states: skeleton loading (shapes matching the
   real content geometry, never a bare spinner), empty (icon + headline + one
   line + an action), error (plain-language cause + a retry that always works),
   and loaded.
2. Loading must never lie — never render a default "free" or "empty" state
   before data arrives.
3. Form errors appear inline beneath their field, never in an alert. Form-level
   problems (offline, rate-limited) go in a banner at the top.
4. No screen may be a dead end. Every error and gate offers a way forward.
5. Design for direct sunlight: high contrast, large targets, no dense toolbars.
6. Money as €120 / €72.50, dates as "Fri 14 Aug", hour ranges as 09:00–11:00,
   relative time as now/4m/2h/3d.

Deliver as a cohesive UI kit with named colour, type and spacing tokens, both
themes, and every component in default / hover / pressed / disabled / busy /
error states.
```

---

## 10. Handover checklist for the design tool output

- [ ] Both themes delivered, light genuinely designed rather than inverted
- [ ] Hero gradient stays dark in both themes
- [ ] microLabel treatment applied consistently
- [ ] Radius 14 is visibly the default shape
- [ ] All four async states exist for every data surface
- [ ] Hour-grid cell designed in all four states, legible in sunlight
- [ ] Status pills cover all five booking states
- [ ] Both role variants of the Home tab
- [ ] Text verified at 1.3× scale without pill overflow
- [ ] Touch targets ≥ 48 dp throughout
