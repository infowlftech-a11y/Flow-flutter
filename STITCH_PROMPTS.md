# FLOW — Stitch prompt pack

Companion to `DESIGN_BRIEF_AND_FIGMA_PROMPT.md`, cut into pieces Stitch can
actually use.

---

## How to use this

1. Go to **stitch.withgoogle.com** → sign in with Google → choose **Mobile**.
2. For each screen: paste **Block A (style)**, then a blank line, then **one**
   screen prompt from below. Never more than one screen per prompt.
3. Generate. Then refine *in the same thread* with short follow-ups —
   "make the hour grid bigger", "show the empty state instead". Iterating in a
   thread keeps the style consistent; starting a new prompt resets it.
4. Repeat for the next screen in a **new** thread, pasting Block A again.

**Why Block A goes in every prompt:** Stitch has no persistent memory of your
brand across separate threads. Re-pasting is what keeps 12 screens looking like
one app instead of 12 apps.

**Order matters.** Do them in the order listed — screens 1–3 establish the
visual language, and once you like those, later screens come out consistent.

**Practical notes**
- Free tier has a monthly generation cap, so don't burn generations on
  variations you already know you don't want.
- Stitch has a higher-quality mode with a lower cap — save it for screens 3 and
  5 (the hour grid and the Command Center), which are the hard ones.
- You can drop an image into a prompt as reference. Your logo is at
  `assets/brand/logo.png`.
- Output is HTML/CSS or a Figma paste — **not Flutter**. Treat it as a picture
  to react to, not code to ship.

---

## BLOCK A — style (paste before EVERY screen prompt)

```
STYLE — apply to this screen:
Mobile app screen, portrait, dark theme. A kitesurfing lesson marketplace on the
Egyptian Red Sea, used one-handed outdoors in bright sunlight.

Colors: background #020A1E, card #041530, elevated card #071C3E, 1px hairline
borders #33355C8F. Accent azure #1DB0FE used ONLY for the active state, the
primary button and the selected value — never for decoration. Text #EFF5FF,
secondary text #A6BAD8, faint text #647CA5. Success #17CE92, warning #FFB547,
danger #FF5D72. Feature and stat surfaces use a 135° navy gradient
#0A2C55 → #041530 with white text.

Type: Sora for headings, tight letterspacing. Inter for body and UI. Every field
label and section header is 11px Inter, weight 700, UPPERCASE, +1.1
letterspacing, in the faint color — this is the signature detail. Money and
times use tabular figures.

Shape: 14px corner radius by default on buttons, cards and inputs; 12px on
chips; 28px on bottom-sheet top corners.

Look: flat, confident minimalism. Solid fills with hairline borders. Depth comes
from color steps, not shadows. NO glassmorphism, NO blur, NO frosted panels, NO
drop shadows, NO gradient text. Generous negative space. Touch targets 48dp+.
```

---

## 1 — Explore (rider home) · *start here*

```
SCREEN: "Explore" — the rider's home tab, a browsable list of kitesurfing
trainers.

Top: screen title "Explore". Below it a search field with a magnifier icon,
placeholder "Search trainers".

Then a horizontally scrolling row of filter chips for kite spots: El Gouna,
Soma Bay, Dahab, Safaga, Hurghada. One chip is selected (azure fill).
To the right of the row, a small sort control reading "Top rated".

Then a vertical list of 4 trainer cards. Each card: circular avatar on the
left; to the right the trainer's name in Sora, the kite spot beneath it in
faint text with a small location pin; a star rating with a numeric value; and
the languages they teach as small outlined tag pills. On the right edge of the
card, the hourly rate as large tabular text ("€80" with "/hour" small beneath
it) and a heart favourite icon in the top corner.

Bottom: a 4-slot bottom navigation bar — Explore (active, azure), Sessions,
Inbox, Profile.
```

---

## 2 — Trainer profile

```
SCREEN: a single trainer's public profile.

Top: a full-width photo gallery header about 40% of screen height, with small
page dots at the bottom and a circular back button floating over it.

Below: the trainer's name in large Sora, kite spot with a pin icon, and a row
with star rating, review count, and years of experience.

Then a section of stat tiles on the dark navy gradient — three across:
hourly rate, sessions taught, response time.

Then "ABOUT" as an uppercase letterspaced micro-label, with a short bio
paragraph. Then "LANGUAGES" with tag pills. Then "REVIEWS" with two review
cards, each showing avatar, name, star rating, relative time and comment text.

A small quiet "Report this trainer" text button at the bottom.

Fixed to the bottom of the screen: a sticky bar with the price on the left
("€80 /hour") and a large azure "Book a session" button on the right.
```

---

## 3 — Booking screen · *the hardest one, use the high-quality mode*

```
SCREEN: booking hours with a trainer. This is the most important screen in the
app — clarity beats beauty.

Top: a compact provider card — small avatar, trainer name, spot, hourly rate.

Then "PICK A DAY" as an uppercase micro-label, and a horizontally scrolling day
strip. Each day is a rounded tile showing weekday abbreviation above the day
number. One is selected with an azure fill; past days are dimmed.

Then "AVAILABLE HOURS" as a micro-label, with a small hint line: "Tap a start
hour, then an end hour — sessions run back-to-back."

Then a grid of hour slots, 3 per row, from 08:00 to 17:00. Each slot shows the
hour. Show ALL FOUR states clearly distinguishable at a glance in sunlight:
- FREE: card fill, hairline border, normal text
- SELECTED: azure fill, dark text, subtle ring
- BOOKED: dimmed, strikethrough or muted, tiny label "Booked"
- TOO SOON: dimmed with a tiny label "Too soon"
Three consecutive slots are selected to show a contiguous range.

Then a summary card: "YOUR SESSION", the date, the hour range "09:00–12:00",
"3 hours × €80", and the total in large tabular text.

Then a multiline message field labelled "MESSAGE TO YOUR TRAINER (OPTIONAL)",
and a toggle row "I need gear" with the subtitle "Kite, board and harness
provided at the centre".

Fixed at the bottom: a sticky bar showing "3 hours · €240" on the left and an
azure "Review & confirm" button on the right.
```

---

## 4 — Sessions (rider bookings)

```
SCREEN: "Sessions" — the rider's bookings.

Top: title "Sessions" and a segmented control with three options: Upcoming
(active), Active, History.

Below: a vertical list of 4 booking cards. Each card has, along the top row, a
status pill and the date. Status pills must be visually distinct:
"Pending" amber, "Confirmed" emerald, "Active" azure, "Completed" faint,
"Cancelled" coral. Under each pill a small explanatory line in faint text
("Waiting for trainer", "Approved", "In progress").

Card body: trainer avatar and name, the hour range "09:00–12:00" in tabular
figures, the kite spot, and the price on the right in tabular figures.

Card footer: for confirmed bookings, an azure outlined button "Show QR ticket"
and a quiet "Cancel" text button. For completed ones, a "Rate your session"
button with small stars.

Bottom: 4-slot bottom navigation, Sessions active.
```

---

## 5 — Command Center, Today tab (trainer home) · *use the high-quality mode*

```
SCREEN: "Command Center" — the trainer's home. Dense but must feel organised.

Top: greeting "Good morning, Omar" in Sora, with today's date beneath in faint
uppercase micro-label.

Then a row of three stat tiles on the dark navy gradient with white text:
"TODAY" 3 sessions · "HOURS" 5h · "EARNINGS" €400. Tabular figures, large.

Then a prominent full-width azure button with a QR icon: "Scan rider in".

Then "PENDING REQUESTS 2" as an uppercase micro-label with a count badge.
Below it, two request cards. Each: rider avatar and name, requested date and
hour range, hours and total price, an optional short message in quotes, and two
actions at the base — an outlined "Decline" and a filled emerald "Approve".

Then "COMING UP" micro-label, and a compact list of today's confirmed sessions
— time on the left in tabular figures, rider name and spot in the middle,
status dot on the right.

Bottom: 4-slot bottom navigation with Home active. A tab bar at the top of the
content area shows "Today" (active) and "Schedule".
```

---

## 6 — Command Center, Schedule tab

```
SCREEN: the trainer's day schedule.

Top: a horizontally scrolling day strip (weekday above day number), one
selected in azure. Above it, the selected date in Sora with "TODAY" as an
uppercase micro-label when applicable, and small arrows to step days.

Main content: a vertical timeline of hours from 08:00 to 18:00. Each row has
the hour on the left in tabular figures, then a wide slot to the right showing
one of:
- FREE: empty card with hairline border and faint "Available"
- BOOKED: filled card with rider avatar, name, and an emerald left edge
- BLOCKED: dimmed card, diagonal hatch, "Unavailable"

Two actions at the bottom, side by side: outlined "Add walk-in" and outlined
"Schedule time off".

Below that, a "TIME OFF" micro-label and one card showing a date range with a
delete icon.
```

---

## 7 — Welcome (auth entry)

```
SCREEN: the app's welcome screen, first thing a new user sees.

Full-bleed dark navy background with a subtle abstract wave silhouette in a
slightly lighter navy at the bottom third.

Centred: a rounded-square app logo mark in azure on ink navy, then the wordmark
"FLOW" in bold Sora, letterspaced.

Below: one short paragraph in faint text, centred: "Kitesurfing lessons on the
Egyptian Red Sea. Find a certified trainer, book hours on the water, check in
on the beach."

Lower third: two stacked full-width buttons — a filled azure "Create an
account" with a small kitesurfing icon, and below it an outlined "I already
have an account".

At the very bottom, small centred fine print in faint text about riding within
your limits and following your trainer's safety briefing.
```

---

## 8 — Create account

```
SCREEN: registration form.

A back arrow top-left over the dark wave background.

Heading in large Sora: "Create your account". Subtitle in faint text: "Takes a
minute. You choose rider or trainer next."

Three fields, each with an UPPERCASE letterspaced micro-label above it:
"YOUR NAME" (placeholder "How trainers will know you"), "EMAIL" (placeholder
"you@example.com"), "PASSWORD" (placeholder "At least 6 characters") with an
eye reveal icon on the right.

Directly under the password field: a thin horizontal strength meter bar about
5px tall, filled two-thirds in amber, with the word "Fair" to its right in the
same amber.

Then a full-width filled azure "Create account" button.

Pinned at the bottom: centred text "Already have an account?" with "Sign in"
in azure beside it.
```

---

## 9 — Role selection

```
SCREEN: choosing your role after signing up.

Dark navy with the wave silhouette. Top-right a quiet "Sign out" text button
with a small icon — there is no back arrow.

Heading in large Sora across two lines: "Who are you on the beach?" Subtitle in
faint text: "This decides what FLOW looks like for you. You only pick once."

Two large tappable cards stacked vertically, each with generous padding:

Card 1: a rounded-square azure-tinted icon holder with a kitesurfer icon,
heading "I'm a Kiter" in Sora, a right-pointing arrow on the far right, a
description line "Find certified trainers, book hours on the water and check in
with a QR ticket", and at the base an uppercase azure micro-label
"RIDE WITH FLOW".

Card 2: same structure with a storefront icon, "I'm a Trainer", description
"Run your calendar, approve requests, scan riders in and track earnings", plus
a small shield icon line in faint text "Trainer accounts are reviewed by our
team before going live", and "WORK WITH FLOW".
```

---

## 10 — Chat

```
SCREEN: a one-to-one conversation between a rider and a trainer.

Top app bar: back arrow, small circular avatar, trainer name with a faint
"Active now" beneath.

Message area: alternating bubbles. Messages from the other person are card-fill
bubbles aligned left with rounded corners; your own messages are azure-filled
bubbles aligned right with dark text. Small faint timestamps under some
bubbles. A centred day divider pill reading "Today". One bubble shows a short
booking reference card inside it — date and hour range.

Floating just above the input: a small azure pill with an up arrow reading
"3 new messages".

Bottom: an input bar with a rounded text field ("Message…") and a circular
azure send button.
```

---

## 11 — QR scanner + ticket (generate as two screens in one thread)

```
SCREEN A: the trainer's QR scanner.
Full-bleed dark camera view. A dark scrim covers everything except a clear
square cutout in the centre with four azure corner brackets. Above the cutout,
white text "Scan the rider's ticket". Below it, faint text "Point at the QR
code on their phone". A close X button top-left. Near the bottom, a coral error
banner with a warning icon reading "This ticket belongs to another trainer".

SCREEN B: the rider's QR ticket, shown as a centred dialog over a dimmed
background. Rounded 20px corners. At the top an emerald "Confirmed" status
pill. Then a large white QR code on a white rounded panel. Beneath it the
trainer name in Sora, the date, and the hour range "09:00–12:00" in large
tabular figures. At the base, faint text "Show this to your trainer at the
beach" and a single "Done" button.
```

---

## 12 — Profile & settings

```
SCREEN: the user's profile and settings.

Heading "Profile" in large Sora.

A grouped card containing three rows, each with a leading icon, a label and a
chevron: "Personal details", "Notifications", "Help & support".

Then an "APPEARANCE" uppercase micro-label, and a three-way segmented control
with the options Auto (selected, azure fill with a check), Light (sun icon),
Dark (moon icon).

Then a "PRIVACY" micro-label with a card row "Security & data" (shield icon),
and a separate card row "Sign out" (logout icon).

Then a "DANGER ZONE" micro-label in coral, and a card row "Delete my account"
in coral with a trash icon.

Centred at the bottom in faint uppercase letterspaced text: "FLOW 3.0.0".

Bottom: 4-slot bottom navigation with Profile active.
```

---

## Extra prompts if you want them

**Empty state** — append to any list screen prompt:
```
Show the EMPTY state instead of content: a centred large faint outline icon, a
short Sora headline, one line of faint explanatory text, and a single outlined
action button.
```

**Loading state** — append to any list screen prompt:
```
Show the LOADING state instead of content: skeleton placeholder shapes that
match the real content's geometry — rounded rectangles where cards go, circles
where avatars go — in a slightly lighter navy than the card fill. No spinner.
```

**Light theme** — append to any prompt:
```
Render this in the LIGHT theme instead: page background #F3F6FB, cards pure
white, hairline borders #1F0A1B36, primary azure #0077C9, text #0A1B36,
secondary #48597B, faint #8393B0. Stat and feature surfaces stay DARK navy
gradient with white text.
```

---

## When you've got designs you like

Bring them back here. Tell me which screens you want and what you liked about
them, and I'll implement it in the real Flutter code — the theme system,
components and screens already exist, so it's editing rather than rebuilding.
Stitch's HTML output is a reference picture, not something that can be dropped
into a Flutter app.
