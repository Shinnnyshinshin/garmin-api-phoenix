# Garmin Workout Planner

A local-only Phoenix web application for coaches and athletes to build structured running workout libraries, define multi-week training plans, and push scheduled workouts to Garmin Connect.

## Stack

| Concern | Technology |
|---|---|
| Backend / frontend | Elixir + Phoenix 1.8 |
| Interactive UI | Phoenix LiveView |
| Database | SQLite via `ecto_sqlite3` |
| Token encryption | `cloak_ecto` (AES-GCM) |
| YAML parsing | `yaml_elixir` |
| Styling | Tailwind CSS + DaisyUI |

## Prerequisites

- Elixir 1.15+ / OTP 26+
- Node.js (for asset building; only needed if editing frontend assets)

Check your version: `elixir --version`

## Running locally

### 1. Install dependencies

```bash
mix deps.get
```

### 2. Set up the database

```bash
mix ecto.create
mix ecto.migrate
```

Or run both at once with the setup alias:

```bash
mix setup
```

### 3. (Optional) Set an encryption key

OAuth tokens are encrypted at rest. In **development**, a safe default key is used automatically. For production or if you want a custom dev key:

```bash
# Generate a key
mix run -e "IO.puts Base.encode64(:crypto.strong_rand_bytes(32))"

# Set it before starting the server
export GARMIN_PLANNER_ENCRYPTION_KEY="<your-base64-key>"
```

### 4. Start the server

```bash
mix phx.server
```

The app runs on [http://localhost:4000](http://localhost:4000) and is accessible to other devices on your local network at `http://<your-machine-ip>:4000`.

> **No authentication**: The app is designed for trusted local network use. Anyone on the network can access it.

## Running tests

```bash
mix test
```

## Project structure

```
lib/
├── garmin_planner/
│   ├── accounts/           # User context + User schema
│   ├── pace_zones/         # PaceZone context + schema
│   ├── workouts/           # Workout context, schema, YAML parser
│   ├── plans/              # TrainingPlan, PlanWeek, PlanWorkout schemas
│   ├── scheduling/         # ScheduledPlan, ScheduledWorkout schemas
│   ├── garmin/             # (Phase 2) Garmin API client stubs
│   └── vault.ex            # Cloak encryption vault
└── garmin_planner_web/
    ├── controllers/        # UserController, PaceZoneController, WorkoutController
    ├── live/               # WorkoutBuilderLive (YAML editor + preview)
    └── components/         # Layouts, CoreComponents
```

## Key features (Phase 1 — this PR)

- **User management**: Create users, assign unit preference (miles/km)
- **Pace zone management**: Per-user pace zones with min/max pace, editable via UI
  - 6 default zones seeded on user creation (easy, moderate, tempo, threshold, 5K pace, interval)
  - Pace stored internally as ms/m, displayed in user's preferred units
- **Workout library**: Card grid of workouts with tag filtering
- **Workout builder (LiveView)**: Split-pane YAML editor with live step preview
  - Debounced parse-on-change (500ms)
  - Step type badges with color coding
  - Supports warmup, cooldown, interval, recovery, rest, repeat groups
- **Garmin auth UI**: Connect/disconnect flow (stub — nimrag fork required for actual OAuth)
- **Full database schema**: All 9 tables for the complete spec are migrated

## What's stubbed / coming next

| Feature | Phase | Notes |
|---|---|---|
| Garmin OAuth exchange | Phase 2 | Requires nimrag fork with SSO endpoints |
| Garmin workout push | Phase 2 | Requires nimrag fork with workout CRUD endpoints |
| Training plan calendar | Phase 3 | LiveView week-by-week table |
| Plan YAML import | Phase 3 | Parser + transactional import |
| Week-by-week push | Phase 4 | Requires `schedule_workout` endpoint discovery via mitmproxy |

## Spec

See [Spec.md](./Spec.md) for the full product and technical specification.

## Environment variables

| Variable | Required | Description |
|---|---|---|
| `GARMIN_PLANNER_ENCRYPTION_KEY` | Dev: optional, Prod: required | Base64-encoded 32-byte AES key for token encryption |
| `DATABASE_PATH` | Prod only | Path to SQLite database file |
| `SECRET_KEY_BASE` | Prod only | Phoenix session secret |
