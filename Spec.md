# Garmin Workout Planner — Product & Technical Specification

## 1. Overview

A local-only Phoenix web application that allows a small group of users (coach + athletes) to build structured running workout libraries, define multi-week training plans, and push scheduled workouts to Garmin Connect automatically.

**Core value proposition**: Compose workouts once in a structured format, organize them into parameterized training plans, and push them to the Garmin calendar week by week with a preview-before-commit flow.

---

## 2. Stack & Constraints

| Concern | Decision |
|---|---|
| Backend / frontend framework | Elixir + Phoenix |
| Interactive UI | Phoenix LiveView (workout builder, plan calendar, push preview) |
| Standard CRUD | Phoenix controllers + HEEx templates |
| Database | SQLite via `ecto_sqlite3` |
| Deployment | Local machine only — no external hosting |
| App-level auth | None — trusted local network access |
| Garmin API client | Fork of [nimrag](https://github.com/arathuku/nimrag) with workout endpoints added |
| Styling | Tailwind CSS (Phoenix default) |
| Token encryption | `cloak_ecto` — OAuth tokens encrypted at rest in SQLite |
| YAML parsing | `yaml_elixir` for plan import |

---

## 3. Users & Garmin Authentication

### 3.1 User Model

There is no app-level login — the app is accessed by anyone on the local network. Each user record represents a person whose Garmin account is managed by the app.

```
users
  id                          integer primary key
  name                        text not null
  display_email               text             -- informational only
  unit_preference             text not null    -- "miles" | "km"
  garmin_username             text             -- display/logging only; not used for auth
  garmin_oauth1_token         text             -- encrypted at rest
  garmin_oauth1_secret        text             -- encrypted at rest
  garmin_oauth1_expires_at    datetime
  garmin_oauth2_access_token  text             -- encrypted at rest
  garmin_oauth2_refresh_token text             -- encrypted at rest
  garmin_oauth2_expires_at    datetime
  garmin_oauth2_refresh_expires_at datetime
  garmin_connected_at         datetime
  inserted_at                 datetime
  updated_at                  datetime
```

### 3.2 Garmin Authentication Flow (Web)

The SSO flow mirrors nimrag's existing auth implementation, adapted for a web request/response cycle:

1. User navigates to **Settings → Connect Garmin Account**
2. User enters their Garmin username and password in a form (HTTPS only; password is never persisted)
3. Phoenix controller initiates the SSO flow (identical to nimrag's `Auth` module)
4. **MFA handling (v1 — low priority)**: If Garmin returns an MFA challenge, the controller stores session state and redirects to an MFA entry form. User enters their TOTP/email code. The flow resumes.
5. On success, OAuth1 + OAuth2 tokens are encrypted and stored in the `users` table
6. The raw Garmin password is discarded immediately after the exchange completes — it is never written to disk or database

### 3.3 OAuth Token Lifecycle

| Token | Lifetime | Refresh mechanism |
|---|---|---|
| OAuth2 access token | ~1 hour | Auto-refreshed before each API call (inherited from nimrag) |
| OAuth2 refresh token | ~90 days | Used to get new access token |
| OAuth1 token | ~1 year | Cannot auto-refresh — requires full re-authentication |

**OAuth1 expiry**: When the app detects an expired OAuth1 token (on any Garmin API call), it redirects the user to a "Reconnect Garmin" page with a clear explanation. The reconnect form is identical to the initial connect flow.

**Encryption**: All token fields use `Cloak.Ecto.Binary` via a symmetric key stored as an environment variable (`GARMIN_PLANNER_ENCRYPTION_KEY`). SQLite stores only ciphertext.

---

## 4. Pace Zone Management

### 4.1 Data Model

```
pace_zones
  id              integer primary key
  user_id         integer not null references users(id)
  name            text not null      -- "easy", "tempo", "threshold", "5K pace", etc.
  label           text               -- display label, e.g. "Easy / Recovery"
  min_pace_ms     integer            -- seconds per meter × 1000 (min of zone = slower bound)
  max_pace_ms     integer            -- seconds per meter × 1000 (max of zone = faster bound)
  color_hex       text               -- UI color for the zone badge
  sort_order      integer
  inserted_at     datetime
  updated_at      datetime
```

Paces are stored internally as **milliseconds per meter** regardless of user unit preference. UI displays and accepts input in the user's preferred unit (min/mile or min/km). Garmin API receives **m/s** derived from these values.

**Conversion**:
- `pace_ms` (ms/m) → Garmin speed (m/s): `1000.0 / pace_ms`
- min/mile → ms/m: `pace_seconds * 1000 / 1609.34`
- min/km → ms/m: `pace_seconds * 1000 / 1000`

### 4.2 Default Zone Names

When a user connects Garmin for the first time, the app seeds a default zone set:

| Zone key | Typical label | Example (for ~3:30 marathon fitness) |
|---|---|---|
| `easy` | Easy / Recovery | 8:30–9:30/mi |
| `moderate` | Moderate / GA | 7:45–8:30/mi |
| `tempo` | Tempo / Comfortably Hard | 7:00–7:30/mi |
| `threshold` | Threshold / LT | 6:50–7:05/mi |
| `5k_pace` | 5K Race Pace | 6:10–6:25/mi |
| `interval` | VO₂max Intervals | 5:55–6:10/mi |

Users edit these via a settings page. The optional "Sync from Garmin" button pulls pace zone settings from Garmin's API and maps them to these named zones.

---

## 5. Workout Library

### 5.1 Data Model

```
workouts
  id                      integer primary key
  user_id                 integer references users(id)
  name                    text not null
  description             text
  sport_type              text not null default "running"
  estimated_duration_secs integer
  steps                   text not null    -- JSON-encoded step tree (see §5.3)
  tags                    text             -- comma-separated for filtering
  inserted_at             datetime
  updated_at              datetime
```

Workouts are user-owned. A `user_id` of NULL could represent system/template workouts in future, but v1 assumes all workouts belong to a user.

### 5.2 Workout Step Types

Mirrors the Garmin Connect workout API types:

| Type | Garmin API key | Description |
|---|---|---|
| `warmup` | `warmup` | Opening step |
| `cooldown` | `cooldown` | Closing step |
| `interval` | `interval` | Active/hard effort |
| `recovery` | `recovery` | Easy effort between intervals |
| `rest` | `rest` | Complete pause |
| `repeat` | `repeat` | Group of steps repeated N times |

### 5.3 Workout Step JSON Schema

Workouts are stored as a JSON array of steps. The `repeat` type contains nested steps.

**ExecutableStep**:
```json
{
  "type": "warmup" | "cooldown" | "interval" | "recovery" | "rest",
  "duration_type": "time" | "distance" | "open",
  "duration_value": 600,
  "duration_unit": "seconds" | "meters" | "miles" | "km",
  "target": {
    "type": "zone" | "pace_range" | "heart_rate_zone" | "none",
    "zone_name": "easy",
    "min_pace": "8:30/mi",
    "max_pace": "9:30/mi"
  }
}
```

**RepeatGroup**:
```json
{
  "type": "repeat",
  "iterations": 5,
  "steps": [
    {
      "type": "interval",
      "duration_type": "distance",
      "duration_value": 1,
      "duration_unit": "miles",
      "target": { "type": "zone", "zone_name": "threshold" }
    },
    {
      "type": "recovery",
      "duration_type": "time",
      "duration_value": 90,
      "duration_unit": "seconds",
      "target": { "type": "zone", "zone_name": "easy" }
    }
  ]
}
```

Target resolution at push time:
- `"zone"` targets: look up the named zone for the user, convert min/max pace to m/s
- `"pace_range"` targets: parse the explicit pace string, convert to m/s
- `"none"`: Garmin `no.target`

### 5.4 Workout Builder UI (LiveView)

The workout builder uses a split-pane LiveView:
- **Left pane**: YAML editor (textarea with monospace font, optional syntax highlighting via JS hook)
- **Right pane**: Structured preview — rendered list of steps with zone badges, estimated duration, and a "Garmin Preview" showing the API payload summary

The YAML input format (see §5.5) is parsed on every change (debounced 500ms). Validation errors appear inline below the editor.

"Save" commits the parsed step tree to the `steps` JSON column. The YAML representation is derived from the stored JSON on load — there is no separate YAML storage.

### 5.5 Workout YAML Input Format

Users write workouts in a simple YAML format. This is converted to the internal JSON step schema.

```yaml
name: "Threshold Intervals"
description: "Classic LT intervals session"
tags: ["threshold", "tuesday"]

steps:
  - type: warmup
    duration: 10min
    target: easy

  - type: repeat
    iterations: 5
    steps:
      - type: interval
        distance: 1mi       # or: duration: 6min
        target: threshold   # named zone key OR explicit pace: "6:50-7:05/mi"

      - type: recovery
        duration: 90sec
        target: easy

  - type: cooldown
    duration: 10min
    target: easy
```

**Duration shorthand**:
- `10min` → 600 seconds
- `90sec` → 90 seconds
- `1mi` → 1 mile (converted to meters in storage)
- `800m` → 800 meters

**Target shorthand**:
- Bare zone key: `easy`, `threshold`, `tempo` — references user's named zone
- Explicit pace range: `"6:50-7:05/mi"` or `"4:15-4:25/km"`
- `open` → no target

**Parser**: Implemented as a pure Elixir module `GarminPlanner.Workouts.YAMLParser`. Returns `{:ok, steps}` or `{:error, reason}` with a human-readable error message.

---

## 6. Training Plans

### 6.1 Data Model

```
training_plans
  id              integer primary key
  user_id         integer not null references users(id)
  name            text not null
  description     text
  total_weeks     integer not null
  sport_type      text not null default "running"
  inserted_at     datetime
  updated_at      datetime

plan_weeks
  id              integer primary key
  plan_id         integer not null references training_plans(id)
  week_number     integer not null    -- 1-based

plan_workouts
  id              integer primary key
  plan_week_id    integer not null references plan_weeks(id)
  day_of_week     text not null       -- "monday" | "tuesday" | ... | "sunday"
  workout_id      integer references workouts(id)   -- null if inline
  inline_steps    text                -- JSON steps if not referencing library workout
  workout_name    text                -- used if inline_steps is set
  distance_override_value  real       -- e.g. "16" for a 16-mile long run (overrides workout step distance)
  distance_override_unit   text       -- "miles" | "km"
  notes           text
```

`plan_workouts.workout_id` is nullable to support plans where a workout is defined inline within the plan (e.g. from a YAML import). Library-referenced workouts carry their step definitions at push time; inline workouts carry their own `inline_steps`.

### 6.2 Plan Calendar View (LiveView)

A week-by-week table with:
- Rows: days of the week (Monday–Sunday)
- Columns: weeks of the plan (Week 1, Week 2, … Week N)
- Cells: workout block (name, estimated distance/time, zone color badges) or "Rest"
- Horizontally scrollable for long plans

Clicking a cell opens a side panel with:
- Full step breakdown
- The option to swap the workout for a different library workout
- Notes field

### 6.3 Plan YAML Import

Users upload a YAML file. The parser creates the plan, weeks, and plan_workout records.

**Format**:
```yaml
name: "18-Week Marathon Plan"
description: "Pfitzinger-style high-mileage build"
total_weeks: 18
sport_type: running

workouts:
  # Inline workout definitions (referenced by key within this file)
  easy_run:
    steps:
      - type: interval    # a plain continuous run uses a single interval step
        distance: "{distance}"   # template variable — filled by each week's assignment
        target: easy

  tempo_run:
    steps:
      - type: warmup
        duration: 10min
        target: easy
      - type: interval
        distance: "{distance}"
        target: tempo
      - type: cooldown
        duration: 10min
        target: easy

  long_run:
    steps:
      - type: interval
        distance: "{distance}"
        target: easy

weeks:
  - week_number: 1
    monday:
      workout: easy_run
      distance: 6mi
      notes: "Keep it easy, first week"
    tuesday:
      workout: tempo_run
      distance: 4mi    # distance of the tempo portion
    wednesday:
      workout: easy_run
      distance: 8mi
    thursday:
      workout: easy_run
      distance: 6mi
    friday: rest
    saturday: rest
    sunday:
      workout: long_run
      distance: 16mi

  - week_number: 2
    monday:
      workout: easy_run
      distance: 7mi
    # ... etc
```

**Template variables**: `{distance}` is substituted per-assignment. This lets one workout template handle varying distances across weeks.

**Referencing library workouts** (instead of inline definitions):
```yaml
weeks:
  - week_number: 1
    tuesday:
      library_workout_id: 42   # references a saved workout by ID
      notes: "Threshold day"
```

**Parser behavior**: The import is transactional. If any week or workout definition fails validation, the entire import is rejected with a detailed error report.

---

## 7. Garmin API Integration

### 7.1 nimrag Fork

Create a fork of nimrag at `lib/nimrag/` (vendored in the Phoenix project as a local dependency via `{:nimrag, path: "../nimrag_fork"}`). All nimrag patterns are preserved:
- `{:ok, data, client}` / `{:error, error}` return tuples
- Client threaded through all calls
- Schematic-based response schemas
- Req middleware stack

### 7.2 New Endpoints to Implement in the Fork

#### `Nimrag.create_workout/2`
```
POST /workout-service/workout
Body: Garmin workout JSON (see §7.3)
Returns: {:ok, %Api.WorkoutCreated{garmin_id: integer, ...}, client}
```

#### `Nimrag.update_workout/3`
```
PUT /workout-service/workout/{garmin_workout_id}
Body: Garmin workout JSON
Returns: {:ok, %Api.WorkoutCreated{}, client}
```

#### `Nimrag.delete_workout/2`
```
DELETE /workout-service/workout/{garmin_workout_id}
Returns: {:ok, :deleted, client}
```

#### `Nimrag.list_workouts/1`
```
GET /workout-service/workouts?start=0&limit=100
Returns: {:ok, list(%Api.WorkoutSummary{}), client}
```

#### `Nimrag.schedule_workout/3` ⚠️ PREREQUISITE
```
POST /workout-service/schedule
Body: {workoutId: integer, date: "YYYY-MM-DD"}
Returns: {:ok, %Api.WorkoutSchedule{garmin_schedule_id: integer}, client}
```

**PREREQUISITE**: This endpoint must be discovered via mitmproxy before the scheduling feature is implemented. Intercept a Garmin Connect web session while scheduling a workout to a date. Capture the request URL, method, headers, and body. Document the response schema.

#### `Nimrag.delete_workout_schedule/2`
```
DELETE /workout-service/schedule/{garmin_schedule_id}
Returns: {:ok, :deleted, client}
```
(Needed for rollback during failed week pushes.)

### 7.3 Garmin Workout Payload Builder

Module `GarminPlanner.Garmin.WorkoutPayload` converts internal step JSON to the Garmin API format:

```elixir
# Input: %Workout{} with resolved pace zones for a specific user
# Output: map ready for JSON encoding and POST to Garmin API

%{
  "workoutName" => workout.name,
  "sportType" => %{"sportTypeId" => 1, "sportTypeKey" => "running", "displayOrder" => 1},
  "estimatedDurationInSecs" => estimated_duration,
  "workoutSegments" => [
    %{
      "segmentOrder" => 1,
      "sportType" => ...,
      "workoutSteps" => [
        # recursive conversion of step tree
      ]
    }
  ]
}
```

Pace zone resolution:
```elixir
# Zone reference → fetch user's pace_zones record → convert ms/m to m/s
def resolve_target(%{"type" => "zone", "zone_name" => name}, user_id) do
  zone = Repo.get_by!(PaceZone, user_id: user_id, name: name)
  %{
    "workoutTargetTypeId" => 4,   # speed
    "workoutTargetTypeKey" => "speed",
    "targetValueOne" => 1000.0 / zone.max_pace_ms,   # faster end = lower pace value
    "targetValueTwo" => 1000.0 / zone.min_pace_ms    # slower end = higher pace value
  }
end
```

### 7.4 Garmin OAuth Client Wrapper

Module `GarminPlanner.Garmin.Client` wraps nimrag client lifecycle for web request use:

```elixir
# Load a nimrag client for a user from their stored (encrypted) tokens
def client_for_user(%User{} = user) do
  oauth1 = %Nimrag.OAuth1Token{...}  # from decrypted user fields
  oauth2 = %Nimrag.OAuth2Token{...}
  Nimrag.Client.new(oauth1_token: oauth1, oauth2_token: oauth2)
end

# After any Nimrag call, persist the (possibly refreshed) OAuth2 token
def persist_updated_client(%User{} = user, client) do
  # Update user record with client.oauth2_token fields
end
```

All Garmin API calls in Phoenix contexts follow this pattern:
```elixir
with client <- GarminClient.client_for_user(user),
     {:ok, result, client} <- Nimrag.create_workout(client, payload),
     :ok <- GarminClient.persist_updated_client(user, client) do
  {:ok, result}
end
```

---

## 8. Workout Push & Scheduling

### 8.1 Garmin Workout Tracking

When a workout is pushed to Garmin (either standalone or as part of a plan), the app records the Garmin-assigned IDs:

```
garmin_workout_pushes
  id                  integer primary key
  workout_id          integer references workouts(id)
  user_id             integer references users(id)
  garmin_workout_id   integer not null    -- assigned by Garmin after create
  pushed_at           datetime
  last_synced_at      datetime
```

```
scheduled_plans
  id              integer primary key
  plan_id         integer not null references training_plans(id)
  user_id         integer not null references users(id)
  start_date      date not null
  status          text not null    -- "draft" | "partially_pushed" | "active"
  inserted_at     datetime
  updated_at      datetime

scheduled_workouts
  id                    integer primary key
  scheduled_plan_id     integer not null references scheduled_plans(id)
  plan_workout_id       integer not null references plan_workouts(id)
  scheduled_date        date not null
  workout_id            integer references workouts(id)
  garmin_workout_id     integer         -- set after push
  garmin_schedule_id    integer         -- set after scheduling to date
  push_status           text not null   -- "pending" | "pushed" | "failed"
  push_error            text            -- error message if failed
  pushed_at             datetime
```

### 8.2 Scheduling a Plan

1. User selects a training plan and picks a **start date** (the date of Day 1 / first Monday of the plan)
2. App computes each workout's calendar date: `start_date + (week_number - 1) * 7 + day_of_week_offset`
3. Creates a `scheduled_plans` record and all `scheduled_workouts` records with `push_status: "pending"`
4. Shows the **Plan Push Preview** (LiveView): week-by-week table with all calculated dates

### 8.3 Week-by-Week Push (LiveView)

**Push Preview screen**: displays the upcoming week's workouts with their scheduled dates and full step details. User clicks "Push Week N to Garmin".

**Atomic push per week** (`GarminPlanner.Garmin.WeekPusher`):
```
For each workout in the week (in order):
  1. Resolve workout steps and pace zones for the user
  2. Build Garmin payload
  3. POST to /workout-service/workout → get garmin_workout_id
  4. POST to /workout-service/schedule with {workoutId, date} → get garmin_schedule_id
  5. Update scheduled_workout record: garmin_workout_id, garmin_schedule_id, push_status: "pushed"

If ANY step fails:
  Rollback: for each successfully pushed workout in this week:
    1. DELETE /workout-service/schedule/{garmin_schedule_id} (if scheduled)
    2. DELETE /workout-service/workout/{garmin_workout_id} (if created)
    3. Reset scheduled_workout.push_status to "pending"
  Return {:error, reason, failed_workout_name}
```

Rate limiting is handled by nimrag's Hammer middleware. If rate limited, the push fails immediately (the atomic rollback fires) and the user is shown a "Rate limited — try again in a moment" message.

**LiveView push UX**:
- "Push Week N" button triggers async push
- Progress indicator shows per-workout status in real time (via LiveView `send` / `assign`)
- On success: week cell turns green, "Week N pushed ✓"
- On failure: detailed error shown, all workouts in the week revert to "pending"

### 8.4 Source of Truth

The app is the source of truth. Garmin Connect is a push target only:
- Edits made in Garmin Connect directly are not synced back
- If a workout is edited in the app after being pushed, a "Re-push" button appears (updates the existing Garmin workout via PUT + re-schedules)
- Users are warned: "Changes made directly in Garmin Connect may be overwritten"

### 8.5 Conflict Handling

When scheduling a plan, the app does not pre-check the Garmin calendar for existing workouts. If a workout already exists on a given date in Garmin Connect, the push proceeds and **overwrites** (plan takes precedence). This matches the "app is source of truth" model.

---

## 9. Phoenix Application Structure

```
garmin_planner/
├── lib/
│   ├── garmin_planner/
│   │   ├── accounts/           # User context
│   │   │   ├── user.ex
│   │   │   └── accounts.ex
│   │   ├── pace_zones/
│   │   │   ├── pace_zone.ex
│   │   │   └── pace_zones.ex
│   │   ├── workouts/
│   │   │   ├── workout.ex
│   │   │   ├── workouts.ex
│   │   │   └── yaml_parser.ex   # YAML → internal step JSON
│   │   ├── plans/
│   │   │   ├── training_plan.ex
│   │   │   ├── plan_week.ex
│   │   │   ├── plan_workout.ex
│   │   │   ├── plans.ex
│   │   │   └── yaml_importer.ex # Plan YAML import
│   │   ├── scheduling/
│   │   │   ├── scheduled_plan.ex
│   │   │   ├── scheduled_workout.ex
│   │   │   ├── scheduler.ex     # Date computation, plan application
│   │   │   └── week_pusher.ex   # Atomic week push + rollback
│   │   └── garmin/
│   │       ├── client.ex         # nimrag client lifecycle for web
│   │       ├── workout_payload.ex # Internal → Garmin API JSON
│   │       └── auth_flow.ex      # SSO flow adapted for web
│   └── garmin_planner_web/
│       ├── controllers/
│       │   ├── user_controller.ex
│       │   ├── garmin_auth_controller.ex  # SSO callback, token storage
│       │   └── plan_import_controller.ex  # YAML file upload
│       ├── live/
│       │   ├── workout_builder_live.ex    # YAML editor + preview
│       │   ├── plan_calendar_live.ex      # Week-by-week plan view
│       │   └── push_preview_live.ex       # Push week UI
│       └── components/
│           ├── step_preview.ex    # Renders a step tree as HTML
│           ├── zone_badge.ex      # Colored zone pill
│           └── push_status.ex     # Per-workout push status indicator
├── priv/
│   └── repo/
│       └── migrations/
└── test/
```

---

## 10. Key Screens

### 10.1 User Management (`/users`)
- List of users with Garmin connection status
- "Connect Garmin" button → `/users/:id/garmin/connect`
- "Reconnect" button if OAuth1 is expired

### 10.2 Garmin Connect Flow (`/users/:id/garmin/connect`)
- Form: Garmin username + password
- MFA step (if triggered): code entry field
- On success: redirect to user settings

### 10.3 Pace Zones (`/users/:id/pace_zones`)
- Table of zones with editable pace range inputs
- Unit toggle (min/mi ↔ min/km)
- "Sync from Garmin" button (optional import)

### 10.4 Workout Library (`/workouts`)
- Card grid of workouts with estimated duration and zone tags
- Filter by tags
- "New Workout" → workout builder
- "Push to Garmin" on individual workout (creates in Garmin library without scheduling)

### 10.5 Workout Builder (`/workouts/new`, `/workouts/:id/edit`) — LiveView
- Split: YAML editor left, step preview right
- Live validation with error messages
- Save button + optional "Save & Push to Garmin Library"

### 10.6 Training Plans (`/plans`)
- List with week count, status
- "New Plan" (manual) or "Import YAML"

### 10.7 Plan Calendar (`/plans/:id`) — LiveView
- Week-by-week table
- Horizontally scrollable
- Click any cell: workout detail side panel
- "Schedule Plan" button → scheduling form

### 10.8 Schedule Plan Form (`/plans/:id/schedule/new`)
- Select user (whose Garmin account to push to)
- Pick start date (date picker)
- Preview computed dates
- "Create Schedule" → creates `scheduled_plan` + `scheduled_workouts`

### 10.9 Push Preview (`/schedules/:id`) — LiveView
- Week-by-week push status view
- Each week shows: dates, workouts, push status (pending/pushed/failed)
- "Push Week N" button per week
- Real-time progress during push

---

## 11. Workout Step Estimation

For `estimated_duration_secs` on the Garmin payload, the app needs to estimate duration from step definitions:

```elixir
# Time-based steps: use duration directly
# Distance-based steps: use midpoint of user's target zone pace × distance
# Repeat groups: sum of inner steps × iterations
# Open steps: use 5-minute default

def estimate_duration(steps, user) do
  Enum.reduce(steps, 0, fn step, acc ->
    acc + step_duration(step, user)
  end)
end
```

This is an estimate only. Garmin Connect displays this value but it doesn't affect device behavior.

---

## 12. Data Validations

### Workout
- `name`: required, max 128 chars
- `steps`: at least 1 step; no more than 50 steps total (Garmin limit); no nested repeat groups (Garmin only supports one level of nesting); warmup must be first if present; cooldown must be last if present

### Plan
- `total_weeks`: 1–52
- No two workouts on the same day within a week
- Distance override must include unit if set

### Pace Zone
- `min_pace_ms` < `max_pace_ms` (slower pace = higher ms/m value, so min/max semantics are "zone lower bound pace" to "zone upper bound pace")
- No overlapping zone ranges for the same user (validation warning, not hard error)

---

## 13. Technical Prerequisites & Risks

| Item | Risk Level | Notes |
|---|---|---|
| Garmin schedule endpoint discovery | **HIGH** — blocks scheduling feature | Must capture via mitmproxy before scheduling is designed. Endpoint path and payload schema unknown. |
| nimrag fork workout endpoints | Medium | Patterns are clear from existing code; schema can be copied from python-garminconnect. Needs test fixtures. |
| Atomic push rollback | Medium | Must handle partial failures and clean up Garmin-side state correctly. |
| SQLite + Cloak token encryption | Low | Well-established libraries. Key management is simple for local-only use. |
| YAML parser coverage | Low-Medium | The grammar is bounded; test extensively against edge cases (nested repeats, missing fields, invalid targets). |
| OAuth1 annual expiry UX | Low | Happens rarely; reconnect flow is identical to initial auth. |

---

## 14. Out of Scope (v1)

- Pulling completed activity data from Garmin (no planned-vs-actual)
- Auto-parameterization of workouts based on fitness (no VDOT/VO₂max scaling)
- Cycling, swimming, or other sport types
- Export/share plans with other users
- Email notifications
- App-level authentication
- Garmin-to-app sync (one-way push only)
- Garmin HR zone targeting (pace zones only for v1)
- Plan duplication/cloning UI (can be added later)

---

## 15. Implementation Phases

### Phase 1: Foundation
- Phoenix project scaffolding (SQLite, Ecto, LiveView, Tailwind)
- nimrag fork setup as local dependency
- User CRUD + Garmin SSO auth flow
- OAuth token encryption with Cloak
- Pace zone management UI

### Phase 2: Workout Library
- Workout model + migrations
- YAML parser module + tests
- Workout builder LiveView (editor + preview)
- Workout CRUD
- Garmin workout payload builder + nimrag `create_workout` endpoint
- Individual workout push to Garmin library

### Phase 3: Training Plans
- Training plan model + migrations
- Plan YAML importer + tests
- Plan calendar LiveView (week-by-week table)
- Manual plan creation UI

### Phase 4: Scheduling & Push (requires mitmproxy discovery first)
- nimrag `schedule_workout` + `delete_workout_schedule` endpoints
- Scheduled plan + scheduled workout models + migrations
- Scheduler module (date computation)
- Push preview LiveView
- Atomic week pusher with rollback
- End-to-end test: plan → schedule → push → verify in Garmin Connect
