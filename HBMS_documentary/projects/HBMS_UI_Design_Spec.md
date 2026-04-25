# HBMS — UI/UX Design Specification
### Agent Execution Prompt — Hotel Booking Management System

---

## 0. Document Purpose

This document is a complete, self-contained execution prompt for a UI/UX agent to implement the
Hotel Booking Management System (HBMS) front-end. All design decisions, component patterns, data
bindings, interaction rules, and visual standards are specified here. The agent must not deviate
from these specifications without explicit override.

---

## 2. Design Language & Token System

### 2.1 Inspiration Reference

Target aesthetic: **Little Hotelier by SiteMinder** — light, clean, hospitality-grade SaaS.
Hallmarks: high information density without clutter, soft teal-blue primary palette, generous
white space on cards, subdued sidebar, prominent CTA buttons, and consistent 8px grid spacing.

### 2.2 Color Tokens (CSS custom properties — `globals.css`)

```css
:root {
  /* Primary — teal-blue (brand) */
  --color-primary-50:  #EFF8FB;
  --color-primary-100: #D0EDF5;
  --color-primary-200: #A1DBEb;
  --color-primary-400: #3AACCF;
  --color-primary-600: #0D87A8;   /* default interactive */
  --color-primary-700: #0A6B87;   /* hover */
  --color-primary-900: #063D4F;   /* text on light */

  /* Neutral */
  --color-neutral-0:   #FFFFFF;
  --color-neutral-50:  #F8FAFB;   /* page background */
  --color-neutral-100: #F1F4F6;   /* sidebar, card backgrounds */
  --color-neutral-200: #E2E8ED;   /* borders, dividers */
  --color-neutral-400: #9AAAB5;   /* placeholder text */
  --color-neutral-600: #5C7080;   /* secondary text */
  --color-neutral-800: #2C3E4A;   /* body text */
  --color-neutral-900: #1A2730;   /* headings */

  /* Semantic */
  --color-success-100: #D4F4E2;
  --color-success-600: #1A9E5C;
  --color-warning-100: #FEF3C7;
  --color-warning-600: #D97706;
  --color-danger-100:  #FEE2E2;
  --color-danger-600:  #DC2626;
  --color-info-100:    #DBEAFE;
  --color-info-600:    #2563EB;

  /* Calendar box states (map to booking_status + room_status) */
  --cal-active:        #3B82F6;   /* Active booking — blue */
  --cal-checked-in:    #0D87A8;   /* Checked-in — teal */
  --cal-dirty:         #F59E0B;   /* Room dirty — amber */
  --cal-maintenance:   #EF4444;   /* Maintenance — red */
  --cal-available:     #10B981;   /* Available — emerald */

  /* Elevation */
  --shadow-sm:  0 1px 2px rgba(0,0,0,.06);
  --shadow-md:  0 4px 12px rgba(0,0,0,.08);
  --shadow-lg:  0 8px 24px rgba(0,0,0,.10);

  /* Radius */
  --radius-sm:  4px;
  --radius-md:  8px;
  --radius-lg:  12px;
  --radius-xl:  16px;
}
```

### 2.3 Typography

```css
/* Font import — Google Fonts */
@import url('https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700&family=DM+Mono:wght@400;500&display=swap');

:root {
  --font-sans: 'Plus Jakarta Sans', system-ui, sans-serif;
  --font-mono: 'DM Mono', ui-monospace, monospace;
}
```

| Scale token | Size | Weight | Usage |
|---|---|---|---|
| `text-display` | 24px / 1.3 | 700 | Page titles |
| `text-heading` | 18px / 1.4 | 600 | Section headings, modal titles |
| `text-subheading` | 14px / 1.4 | 600 | Card labels, table headers |
| `text-body` | 14px / 1.5 | 400 | Body copy, form labels |
| `text-small` | 12px / 1.5 | 400 | Helper text, timestamps |
| `text-mono` | 13px / 1.4 | 500 | IDs, amounts, codes |

### 2.4 Spacing Grid

Base unit = **4px**. Use only multiples: `4, 8, 12, 16, 20, 24, 32, 40, 48, 64`.
Sidebar width: `240px`. Content max-width: `1280px`. Panel gutter: `24px`.

### 2.5 Component Tokens

```
Button height:      36px (default), 32px (sm), 40px (lg)
Input height:       36px
Table row height:   48px
Sidebar item:       40px
Modal max-width:    560px (sm), 720px (md), 960px (lg)
```

---

## 3. Global Layout Shell

```
┌─────────────────────────────────────────────────────────────────┐
│  TOPBAR  [Logo]  [Hotel name]                  [User]  [Bell]   │  h=56px
├──────────┬──────────────────────────────────────────────────────┤
│          │                                                      │
│ SIDEBAR  │  MAIN CONTENT AREA                                   │
│ 240px    │  padding: 24px                                       │
│          │  background: --color-neutral-50                      │
│          │                                                      │
└──────────┴──────────────────────────────────────────────────────┘
```

### Sidebar Nav Items (icons + labels)

```
[CalendarDays]   Calendar         → /calendar
[PlusSquare]     New Reservation  → /reservations/new
[BarChart2]      Statistics       → /statistics
─────────────────────────────────
[Settings]       Settings
[LogOut]         Sign out
```

Active item: `background: --color-primary-50; color: --color-primary-700; font-weight: 600; border-right: 3px solid --color-primary-600`.

---

## 4. View: Add Reservation (`/reservations/new`)

### 4.1 Layout

```
Page Title: "New Reservation"  [breadcrumb: Home > Reservations > New]

┌──────────────────────────────┬────────────────────────────────────┐
│  LEFT PANEL (48%)            │  RIGHT PANEL (52%)                 │
│  "Room Search & Selection"   │  "Reservation Form"                │
└──────────────────────────────┴────────────────────────────────────┘
```

Both panels are white cards (`bg-white rounded-lg shadow-sm border border-neutral-200 p-6`).
Panels are sticky to viewport top when scrolling content below.

---

### 4.2 Left Panel — Room Search & Selection

#### Search Bar

```
┌──────────────────────────────────────────────────────────┐
│  Check-in [DateTimePicker ▼]   Check-out [DateTimePicker ▼]   [Search ▶] │
└──────────────────────────────────────────────────────────┘
```

- `DateTimePicker`: shows date + time (TIMESTAMP). Default check-in = today 14:00, check-out = tomorrow 12:00.
- **[Search]** button: primary, calls `search_available_rooms(check_in::DATE, check_out::DATE)`.
- While loading: skeleton rows (3 rows, animated pulse).

#### Available Rooms Table

```
┌──────────────┬──────────┬──────────────┬────────────────┬──────────┐
│ Room Type    │ Available│ Price/Night  │ Warning        │ Action   │
├──────────────┼──────────┼──────────────┼────────────────┼──────────┤
│ Deluxe King  │   4      │  VND 850,000 │                │ [+ Add]  │
│ Twin Standard│   0      │  VND 650,000 │                │ [+ Add]  │← disabled
│ Suite        │   2      │ VND 1,500,000│⚠ Missing data  │ [+ Add]  │
└──────────────┴──────────┴──────────────┴────────────────┴──────────┘
```

- `min_available = 0`: row grayed out (`opacity-50`), [+ Add] disabled.
- `has_missing_dates = TRUE`: amber badge `⚠ Incomplete inventory` with tooltip "Inventory data missing for some dates in range".
- Prices formatted as locale currency string (`Intl.NumberFormat`).

#### Add to Order Popover (triggered by [+ Add])

Appears as a small popover anchored below the row button:

```
┌──────────────────────────────────┐
│  Deluxe King                     │
│  Quantity: [─] [2] [+]  (max: 4) │
│  ☑ Include Breakfast             │
│  [Add to Reservation]            │
└──────────────────────────────────┘
```

- Quantity stepper: min=1, max=`min_available`, integer only.
- Checkbox for `is_breakfast_included`.
- On submit: appends to **Room Selection Staging** (Zustand store), closes popover.
- Constraint: if `room_type_id` already in staging → shows inline error "Already added. Remove existing entry to change."

#### Room Selection Staging (below table)

Label: "Selected Rooms" with badge showing count.

```
┌───────────────────┬────────┬──────────────┬──────────┬──────────┐
│ Room Type         │  Qty   │  Breakfast   │ Subtotal │          │
├───────────────────┼────────┼──────────────┼──────────┼──────────┤
│ Deluxe King       │   2    │  ✓ Yes       │ 3,400,000│ [✕]      │
│ Suite             │   1    │  – No        │ 6,000,000│ [✕]      │
└───────────────────┴────────┴──────────────┴──────────┴──────────┘
                                      Subtotal (rooms): 9,400,000 VND
```

Subtotal = `agreed_price × quantity × nights` (nights calculated from date range). Amounts shown in `text-mono` style.

---

### 4.3 Right Panel — Reservation Form

Structured as sequential **sections** separated by a thin divider line with section label.

#### Section 1: Guest Information

```
Phone Number  [_______________]  [🔍 Search]
```

On search by phone:
- **Found**: auto-fill fields below, show green checkmark badge "Existing guest — John Doe".
- **Not found**: fields remain editable, show info badge "New guest — profile will be created".

```
Full Name *    [________________________]
Email          [________________________]
ID / Passport  [________________________]
Date of Birth* [──── DD/MM/YYYY ────]   ← must be ≥ 18 years old (validated client + server)
```

All fields use standard `Input` component, 36px height, `rounded-md border-neutral-200 focus:border-primary-600 focus:ring-1 focus:ring-primary-600`.

#### Section 2: Selected Rooms (read-only mirror of Staging)

Compact table, no actions. Columns: Room Type, Qty, Breakfast, Unit Price, Subtotal.
Shows "No rooms selected yet" empty state with illustrated icon when staging is empty.

#### Section 3: Additional Services

```
[+ Add Service]
```

Button triggers **Service Search Modal** (see §4.4).

Staging table:
```
┌──────────────────┬──────────┬──────────┬──────────┐
│ Service          │ Unit Price│  Qty     │ Subtotal │
├──────────────────┼──────────┼──────────┼──────────┤
│ Airport Transfer │  350,000 │    2     │  700,000 │  [✕]
│ Spa Treatment    │  500,000 │    1     │  500,000 │  [✕]
└──────────────────┴──────────┴──────────┴──────────┘
```

#### Section 4: Surcharges (visible only after successful booking finalization)

Read-only. Each surcharge displayed as a slim row:
```
  EarlyCheckIn   Early check-in before 10:00       +200,000 VND
  Weekend        Weekend rate applied               +400,000 VND
```

#### Section 5: Price Summary (sticky at bottom of right panel)

```
┌──────────────────────────────────────────┐
│  Room cost        9,400,000              │
│  Surcharges            600,000           │
│  Services          1,200,000             │
│  ──────────────────────────────          │
│  TOTAL            11,200,000 VND         │
└──────────────────────────────────────────┘

         [Cancel]          [Book Now →]
```

- TOTAL row: `text-heading font-700 text-primary-700`.
- [Book Now]: primary CTA button, full-width, `h-10`, disabled when staging is empty or required guest fields are invalid.
- [Cancel]: ghost button.

---

### 4.4 Service Search Modal

```
┌────────────────────────────────────────────────────┐
│  Add Service                                   [✕] │
├────────────────────────────────────────────────────┤
│  [🔍 Search services...                        ]   │
│                                                    │
│  Results                                           │
│  ┌──────────────────┬──────────┬─────────┬──────┐  │
│  │ Service          │ Category │  Price  │      │  │
│  ├──────────────────┼──────────┼─────────┼──────┤  │
│  │ Airport Transfer │ Transport│ 350,000 │[Add] │  │
│  │ Breakfast Buffet │ F&B      │ 180,000 │[Add] │  │
│  └──────────────────┴──────────┴─────────┴──────┘  │
│                                                    │
│  Qty for selected: [─] [1] [+]                     │
└────────────────────────────────────────────────────┘
```

- Debounced search input (300ms) → calls `search_services(hotel_id, keyword)`.
- [Add] inline: selects row, enables quantity stepper, then [Confirm] appends to Service Staging.

---

### 4.5 Booking Submission Flow & Error Handling

The agent executing the backend calls must follow the 6-step DB flow from the scenario exactly.
In the UI, these steps are represented as a **progress indicator** shown while loading:

```
● Creating guest profile…
● Initializing booking…
● Adding room details…
● Finalizing & applying surcharges…
● Recording services…
✓ Done — redirecting to payment…
```

Error toasts (sonner):

| Error Code | Toast Message | Action |
|---|---|---|
| `P0001` OVERBOOKING | "Room unavailable on [date] — please adjust your selection" | Re-highlight affected row |
| `P0002` DUPLICATE | "Duplicate request detected — retrying…" | Auto-retry with new idempotency_key |
| `P0003` SYSTEM | "Inventory not configured. Contact administrator." | — |
| `P0005` INVALID_PERIOD | "Check-out must be after check-in" | Focus date fields |
| `P0006` INVALID_QUANTITY | "Quantity exceeds available inventory" | Focus quantity input |

---

## 5. View: Payment (`/reservations/:id/payment`)

### 5.1 Layout

Single-column, max-width 800px, centered. White card sections.

```
← Back to Reservations

Booking #BK-00412  •  John Doe  •  3 nights

┌─────────────────────────────────┬─────────────────────────────┐
│  BOOKING SUMMARY                │  PAYMENT ACTIONS            │
└─────────────────────────────────┴─────────────────────────────┘
```

### 5.2 Booking Summary Card

Sourced from `v_booking_summary`:

```
Guest          John Doe
Phone          0901 234 567
Room(s)        Deluxe King (×2), Suite (×1)
Check-in       Fri, 25 Apr 2026 · 14:00
Check-out      Mon, 28 Apr 2026 · 12:00
Nights         3
```

Below, three collapsible sub-sections:

**Rooms Breakdown** — agreed_price × quantity × nights per line
**Surcharges** — from `booking_surcharges`
**Services** — from `service_usage JOIN services`

Each section shows line items + section subtotal.

```
TOTAL            11,200,000 VND
Paid                       0 VND
Balance due      11,200,000 VND   ← highlighted red if > 0
```

### 5.3 Payment Actions Card

```
┌──────────────────────────────────────────┐
│  Invoice                                 │
│  Status: [Draft badge]                   │
│                    [Issue Invoice →]     │
├──────────────────────────────────────────┤
│  Record Payment                          │
│  Amount  [VND ___________________]       │
│  Method  [Cash ▼]  (UI only, not saved)  │
│                   [Record Payment ✓]     │
└──────────────────────────────────────────┘
```

- **[Issue Invoice]**: calls `issue_invoice(booking_id, staff_id)` → badge changes to `Issued` (blue). Button becomes disabled.
- **[Record Payment]**: calls `record_payment(booking_id, amount, staff_id)` → updates balance display.
  - When `balance = 0`: balance badge turns green "Paid in full", triggers `tetrisroom_defrag(hotel_id, staff_id)` call, shows toast "Payment complete — rooms assigned to calendar".
  - Quick-fill buttons: [25%] [50%] [Full amount] pre-fill the amount input.

Invoice status badge variants:
- Draft → `bg-neutral-100 text-neutral-600`
- Issued → `bg-info-100 text-info-600`
- Paid → `bg-success-100 text-success-600`
- Void → `bg-danger-100 text-danger-600`

---

## 6. View: Calendar (`/calendar`)

### 6.1 Layout

```
[← Prev Week]  [25 Apr 2026 — 01 May 2026]  [Next Week →]   [Today]   [+ New Reservation]   [Defragment ⚡]

┌────────────────────────────────────────────────────────────────────┐
│          │  Fri 25  │  Sat 26  │  Sun 27  │  Mon 28  │  ...        │
├──────────┼──────────┼──────────┼──────────┼──────────┼─────────────┤
│ Deluxe King  (header row, merged, bg neutral-100)                   │
│  Room 101│ [■■■■■■]             │          │ [■■■■]   │             │
│  Room 102│          │ [■■■■]   │          │          │             │
├──────────┼──────────┼──────────┼──────────┼──────────┼─────────────┤
│ Suite        (header row)                                           │
│  Room 201│ [■■]     │          │ [■■■■■]  │          │             │
└──────────┴──────────┴──────────┴──────────┴──────────┴─────────────┘
```

- Date range: 7 days default; user can switch to 14 or 30-day view via toggle.
- Column width: `(total width - 120px room label) / day count`.
- Room label column: 120px, sticky left.

### 6.2 Booking Blocks

Each block = a `room_assignment` row from `v_calendar`.

```
┌──────────────────────────────────────────────────────────┐
│                                                          │
│  [avatar initials] John D. — BK-00412                   │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

Block width = proportional to `(check_out - check_in)` days within the visible range.
Block height = row height `48px` minus `4px` top/bottom padding.

**Block color by booking_status:**
- `Active` (pre-assigned, not yet checked in): `bg-cal-active/20 border-2 border-cal-active border-dashed text-cal-active`
- `Checked-in`: `bg-cal-checked-in/20 border-2 border-cal-checked-in text-cal-checked-in` (solid border)

**Block color override by room_status:**
- `Dirty`: amber diagonal stripe overlay
- `Maintenance`: red overlay, lock icon, non-interactive

Avatar: circular, 20px, initials from `customer_name`, color seeded from `booking_id`.

### 6.3 Hover Behavior

When hovering any block, ALL blocks with the same `booking_id` (multi-room booking) highlight together:
- Others get `ring-2 ring-primary-400` outline.
- Tooltip appears above hovered block:
```
BK-00412 · John Doe · 0901 234 567
Check-in: 25 Apr 14:00  Check-out: 28 Apr 12:00
Total: 11,200,000 · Paid: 11,200,000 · Balance: 0
```

### 6.4 Click — Detail Side Panel

Clicking a block opens a **slide-in panel** from the right (320px wide, overlays content):

```
Booking #BK-00412                     [✕]
─────────────────────────────────────
Guest    John Doe
Phone    0901 234 567
─────────────────────────────────────
Check-in    Fri 25 Apr 14:00
Check-out   Mon 28 Apr 12:00
Room        Room 101 — Deluxe King
─────────────────────────────────────
Amount       11,200,000
Paid         11,200,000
Balance              0     ✓ Paid
─────────────────────────────────────
Booking status   Active
Room status      Available
─────────────────────────────────────
[View full reservation →]
[Check In]       (only if Active)
[Check Out]      (only if Checked-in)
```

### 6.5 Drag & Drop (vertical only)

- Draggable: only blocks with `booking_status = Active` (pre-assigned, not yet checked in).
- Drag axis: **vertical only** (Y-axis) within the same `room_type_id` group.
- Ghost element: semi-transparent copy of block at 60% opacity, follows cursor.
- Drop targets: other room rows of the same `room_type_id`.
- Conflict detection: before allowing drop, check for existing blocks on overlapping dates.
  - Valid drop → green highlight on target row.
  - Invalid drop (conflict) → red highlight + cursor `not-allowed`.
- On successful drop:
  1. Optimistic UI: block moves immediately.
  2. API: `CALL pre_assign_room(booking_id, new_room_id, staff_id)` (cancels old assignment first).
  3. On error: revert block to original position, show error toast.

### 6.6 Defragment Button

`[Defragment ⚡]` — secondary button, top-right of calendar header.

On click: confirmation dialog:
```
Defragment Room Assignments?

This will re-pack all Active pre-assignments to minimize
room fragmentation. Checked-in guests will not be affected.

[Cancel]   [Defragment →]
```

On confirm: calls `tetrisroom_defrag(hotel_id, staff_id)`. Shows loading spinner overlay on calendar.
On complete: re-fetches `v_calendar` and re-renders. Success toast: "Rooms defragmented successfully."

---

## 7. View: Statistics (`/statistics`)

### 7.1 Layout

```
Page Title: "Statistics & Reports"

[Date Range Picker: Month ▼]  [Room Type: All ▼]   [Export CSV]

┌────────────────────────────────────────────────────────────────┐
│  OCCUPANCY HEATMAP                               (full width)  │
├──────────────────────────────────────┬─────────────────────────┤
│  MONTHLY REVENUE (stacked bar chart) │  REVENUE BREAKDOWN PIE  │
└──────────────────────────────────────┴─────────────────────────┘
```

### 7.2 KPI Summary Row (above charts)

Four stat cards in a 4-column grid:

```
┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│ Avg Occupancy│ │ Total Revenue│ │  Collected   │ │ Outstanding  │
│    78.4%     │ │ 128,400,000  │ │ 110,200,000  │ │  18,200,000  │
│ ↑ +5.2% MoM  │ │ ↑ +12% MoM  │ │              │ │   (balance)  │
└──────────────┘ └──────────────┘ └──────────────┘ └──────────────┘
```

Cards: white, `shadow-sm`, left border accent (`border-l-4 border-primary-600`).

### 7.3 Occupancy Heatmap

Source: `v_daily_occupancy`. Rows = room types, columns = dates.

```
             Apr 25   Apr 26   Apr 27   ...
Deluxe King  [████]   [██░░]   [████]
Suite        [██░░]   [████]   [░░░░]
Twin         [░░░░]   [██░░]   [████]

Legend:  0%─────────────────────100%
         ░░░░░░░████████████████
         (white)              (primary-600)
```

Cell color interpolates between `--color-neutral-100` (0%) and `--color-primary-600` (100%).
Tooltip on hover: "Deluxe King · Apr 26 · 2/4 rooms · 50% occupied".

### 7.4 Monthly Revenue Stacked Bar Chart (Recharts)

Source: `v_monthly_revenue`. X-axis = months, Y-axis = VND (formatted in millions).

```
Bars (stacked, bottom to top):
  1. total_room_cost    — color: --color-primary-400
  2. total_surcharges   — color: --color-warning-600
  3. total_services     — color: --color-success-600

Line overlay:
  actual_collected      — color: --color-primary-900, dashed
```

Legend below chart. Tooltip shows breakdown on hover.

### 7.5 Revenue Breakdown Donut Chart (Recharts)

Shows current selected period breakdown:

```
  Rooms:      74%   (primary-400)
  Surcharges:  9%   (warning-600)
  Services:   17%   (success-600)
```

Center text: Total revenue for period.

---

## 8. Shared Components Specification

### 8.1 DataTable

Standard table used throughout the app:

- `<thead>`: `bg-neutral-50 text-subheading text-neutral-600 uppercase tracking-wide text-xs`
- `<tbody tr>`: hover `bg-neutral-50`, selected `bg-primary-50`
- Borders: `border-b border-neutral-200` on rows
- Empty state: centered illustration + message, minimum 200px height

### 8.2 StatusBadge

```tsx
<StatusBadge status="Active" />  // → teal
<StatusBadge status="Pending" /> // → amber
<StatusBadge status="Checked-in" /> // → blue
<StatusBadge status="Completed" /> // → green
<StatusBadge status="Cancelled" /> // → red
```

All badges: `rounded-full px-2.5 py-0.5 text-xs font-medium`.

### 8.3 DateTimePicker

- Renders as an input with popover calendar.
- Calendar: month view, navigable, date range selection for check-in/out pair.
- Time: separate HH:mm spinners below calendar.
- Disabled dates: visually crossed, non-selectable (check-out cannot precede check-in).

### 8.4 CurrencyInput

- Prefix slot: `VND`
- Formats value with thousands separators while typing (`Intl.NumberFormat`).
- Internal value: raw `Decimal`.
- Quick fill buttons: configurable (e.g., [25%] [50%] [Full]).

### 8.5 ConfirmDialog

Standard Radix `AlertDialog` wrapper:

```
Title, description, [Cancel (outline)] [Confirm (destructive/primary)]
```

Used for defragment, cancellation, void invoice.

---

## 9. Form Validation Rules (Zod schema, mirrors DB constraints)

```typescript
const guestSchema = z.object({
  full_name:     z.string().min(1, "Required"),
  phone_number:  z.string().regex(/^\d{9,11}$/, "Invalid phone"),
  email:         z.string().email().optional().or(z.literal("")),
  identity_card: z.string().optional(),
  date_of_birth: z.date().refine(
    d => differenceInYears(new Date(), d) >= 18,
    "Guest must be at least 18 years old"
  )
});

const roomSelectionSchema = z.object({
  room_type_id:         z.number(),
  quantity:             z.number().int().min(1),
  is_breakfast_included: z.boolean()
}).array().min(1, "Select at least one room");

const paymentSchema = z.object({
  amount: z.number().positive("Amount must be greater than 0")
});
```

---

## 10. Accessibility Requirements

- All interactive elements must have visible focus rings (2px primary-600).
- Table headers: `role="columnheader"`, `scope="col"`.
- Modal dialogs: trap focus, Escape closes, `aria-labelledby`.
- Calendar blocks: `role="button"`, `aria-label="Booking BK-00412, John Doe, Room 101, Apr 25–28"`.
- Drag handles: keyboard alternative via context menu [Move to…] > room selector.
- Color is never the sole differentiator: use icons and text alongside status colors.
- Contrast ratio: minimum 4.5:1 for all text (WCAG AA).

---

## 11. Loading & Empty States

| Situation | Treatment |
|---|---|
| Data fetching (table) | Skeleton rows: animated pulse, same row height |
| Data fetching (chart) | Gray placeholder rectangle with spinner |
| Empty table | Centered icon (Lucide) + heading + optional CTA |
| Error state | Red banner with icon, error message, [Retry] button |
| Optimistic update | Immediate UI change + subtle loading spinner on affected element |

---

## 12. Responsive Behavior

Target: Desktop-first (min 1024px). Tablet support (768px–1024px) via:
- Sidebar collapses to icon-only rail (48px).
- Left/right panels on Add Reservation stack vertically.
- Calendar switches to single-column (one room type visible, swipe to navigate).

Mobile (< 768px): out of scope — show "Please use desktop" banner.

---

## 13. Performance Targets

| Metric | Target |
|---|---|
| LCP | < 2.0s |
| CLS | < 0.1 |
| TanStack Query cache | staleTime: 30s for room availability, 5min for statistics |
| Calendar re-render | Virtualize rows if > 50 rooms (react-virtual) |
| Search debounce | 300ms (services), 500ms (guests) |

---

*End of HBMS UI Design Specification v1.0*
