# PROJECT BRAIN — Job Requisition Analytics Dashboard

> **What this document is:** the complete working knowledge of this project —
> architecture, data flow, every file, the full database schema (base + all
> migrations), the deploy model, and a step-by-step **fresh setup guide for a
> new client**. Written to be self-contained: hand it to anyone (or any AI) and
> they can stand up a new instance from scratch.
>
> Original instance: **Citadel Reporting**. Repo: `Developertechnokrats/citadel-reporting`.
> Generated: 2026-10-27.

---

## 0. TL;DR — What this system is

A **webhook receiver + analytics dashboard** that:

1. Receives GoHighLevel (GHL) **Job Requisition** webhooks (full JSON payload).
2. Stores every event in **Supabase (Postgres)**.
3. Tracks each job's **open→close cycles** (a job can be opened/closed many times).
4. Computes **Days to Hire** and **% Time to Hire** per cycle.
5. Serves a filterable **dashboard** (summary cards + table + detail modal) and
   **region-locked embeddable URLs**.

- **Hosting / webhook + API:** Netlify (static site + Netlify Functions)
- **Database:** Supabase (Postgres)
- **Source system:** GoHighLevel — custom object "Job Requisition"

### Critical fact for replication
**The app NEVER calls the GHL API.** It only *receives* webhooks that GHL pushes
to it. The only secrets the code uses are `SUPABASE_URL`, `SUPABASE_SERVICE_KEY`,
and `WEBHOOK_SECRET`. A client's **GHL Location ID / API key are NOT used by this
codebase** — GHL just needs to be *configured* to POST its webhook to the
Netlify URL with the right secret header. (So for the new client, you set up GHL
to send webhooks; you do not put their GHL key anywhere in this app.)

---

## 1. Architecture & data flow

```
GoHighLevel (Job Requisition created / status changed)
        │   POST full JSON payload, header: X-Webhook-Secret
        ▼
Netlify Function:  job-requisition.js        (ingest endpoint)
        │   upsert + cycle logic + audit log
        ▼
Supabase (Postgres)
   • job_requisitions   — master, one row per TrackTik Post ID
   • job_cycles         — one row per open→close cycle
   • job_status_history — full audit log of every webhook hit
   • import_batches     — CSV import audit + undo
   • manual_corrections — admin edit audit trail
        │
        ▼
Netlify Functions (read/aggregate):
   • dashboard-data.js  — summary cards, table, filter options
   • job-detail.js      — single job + its cycles + history (modal)
   • region-report.js   — region-scoped report
   • import-csv.js      — CSV bulk import
   • undo-import.js     — revert a CSV import batch
   • edit-cycles.js     — admin manual cycle edits
        │
        ▼
Static dashboard (/public): index.html, app.js, styles.css,
   jobs.html, admin.html, reports.html, region-report.html, import.html
```

### URL routing (netlify.toml)
- `POST /webhook/*` → `/.netlify/functions/:splat`  → e.g. `/webhook/job-requisition`
- `GET|POST /api/*` → `/.netlify/functions/:splat`   → e.g. `/api/dashboard-data`
- Publish directory: `public`
- Functions directory: `netlify/functions`
- Bundler: `esbuild`; `netlify dev` runs on port 8888

---

## 2. Repository layout

```
/netlify/functions/
    job-requisition.js   # GHL webhook ingest (upsert + cycle tracking + audit)
    dashboard-data.js    # dashboard query/aggregation (summary cards, table, filters)
    job-detail.js        # one job's full detail for the modal (select *)
    region-report.js     # region-scoped reporting endpoint
    import-csv.js        # CSV bulk import
    undo-import.js       # revert a CSV import batch
    edit-cycles.js       # admin manual cycle edits (writes manual_corrections)
/public/
    index.html           # main dashboard UI (summary cards + filters + table)
    app.js               # dashboard logic: filters, fetch, render, modal, region lock
    styles.css           # all styling (summary-strip grid, cards, modal, table)
    jobs.html            # (secondary page)
    admin.html           # admin tools UI
    reports.html         # reports UI
    region-report.html   # region report UI
    import.html          # CSV import UI
/supabase/
    schema.sql                        # base tables, indexes, RLS, RPC
    migration_001_needs_review.sql    # needs_review + review_notes columns
    migration_002_cycle_source.sql    # job_cycles.source column (ghl|csv)
    migration_003_corrections.sql     # manual_corrections table
    migration_import_batches.sql      # import_batches table (if not already in schema.sql)
    correction_001_delayed_webhooks.sql  # ONE-TIME Citadel data fix — DO NOT run for new client
    cleanup_001_pre_apr2026.sql           # ONE-TIME Citadel data purge — DO NOT run for new client
    cleanup_002_managers.sql              # ONE-TIME Citadel name fixes — DO NOT run for new client
/supabasebackup/          # database dumps (.dump / .sql) — Citadel data, reference only
netlify.toml              # routing, publish dir, functions, dev port
package.json              # deps: @supabase/supabase-js, csv-parse; devDep: netlify-cli
DEPLOYMENT.md             # original deploy guide + curl test commands
README.md                # product spec (base design)
```

---

## 3. Database schema — complete current state

> For a **fresh** database, apply, in order: `schema.sql` → `migration_001` →
> `migration_002` → `migration_003` → **the `hiring_needs` ALTER below**.
> (`migration_import_batches.sql` is already covered by `schema.sql`, which
> creates `import_batches`; it's only for upgrading an older deploy.)
> **Do NOT** run the `correction_*` / `cleanup_*` scripts — those are one-time
> fixes against Citadel's real data.

### Table: `job_requisitions` (master — one row per TrackTik Post ID)
- `id` UUID PK, `tracktik_post_id` TEXT UNIQUE NOT NULL, `ghl_id` TEXT
- Job fields (all TEXT): `advertised_pay_rate`, `applicant_radius`,
  `applicant_stack_status`, `city_of_site_location`, `disqualifying_questions`,
  `employment_status`, `hiring_manager`, `hr_approval_status`,
  `in_person_interview_address`, `industry`, `interview_calendar`,
  `interview_type`, `job_duties`, `officer_type`, `other_preferences`,
  `position_specific_requirements`, `position_start_date`, `position_status`,
  `preferred_screening_questions`, `region`, `schedule`, `serviceable_zip_code`,
  `site_name_position_shift`, `state_of_site_location`, `tier1_zip_codes`,
  `tier2_zip_codes`, `tier3_zip_codes`, `tracktik_site_id`, `zip_code_of_site`
- `current_status` TEXT DEFAULT 'created'  (created | open | closed)
- `total_cycles` INT DEFAULT 0
- `first_seen_at`, `created_at`, `updated_at` TIMESTAMPTZ DEFAULT NOW()
- **migration_001:** `needs_review` BOOLEAN DEFAULT FALSE, `review_notes` TEXT
- **manual ALTER (not yet a migration file):** `hiring_needs` INTEGER NULL

### Table: `job_status_history` (audit — every webhook hit, forever)
- `id` UUID PK, `tracktik_post_id` TEXT FK→job_requisitions (ON DELETE CASCADE)
- `status` TEXT (created | open | closed), `cycle_number` INT
- `recorded_at` TIMESTAMPTZ, `raw_payload` JSONB (full GHL JSON)

### Table: `job_cycles` (one row per open→close cycle)
- `id` UUID PK, `tracktik_post_id` TEXT FK→job_requisitions (ON DELETE CASCADE)
- `cycle_number` INT NOT NULL, `opened_at`, `closed_at` TIMESTAMPTZ
- `days_to_hire` NUMERIC(10,2), `pct_time_to_hire` NUMERIC(10,2)
- `is_open` BOOLEAN DEFAULT TRUE
- `created_at`, `updated_at` TIMESTAMPTZ
- UNIQUE(`tracktik_post_id`, `cycle_number`)
- **migration_002:** `source` VARCHAR(10) DEFAULT 'ghl'  (ghl | csv)

### Table: `import_batches` (CSV import audit + undo)
- `id` UUID PK, `filename` TEXT, `imported_at` TIMESTAMPTZ
- `total_jobs` INT, `total_cycles` INT, `status` TEXT DEFAULT 'completed' (completed | reverted)
- `snapshot` JSONB (pre-import state for undo)

### Table: `manual_corrections` (migration_003 — admin edit audit, never read by dashboard)
- `correction_type` VARCHAR(50) (cycle_edit | cycle_add | cycle_delete | bulk_import)
- `before_state` JSONB, `after_state` JSONB, `note` TEXT
- `tracktik_post_id`, `created_at` (+ indexes)

### RPC / function: `recalculate_pct_time_to_hire(p_tracktik_post_id TEXT)`
- Sums all closed cycles' `days_to_hire` for the job, then sets each cycle's
  `pct_time_to_hire = days_to_hire / total_days * 100`. Called by the webhook
  after every close event.

### Row Level Security (RLS)
- Enabled on all tables.
- `service_role` → full access (used by Netlify Functions via the service key).
- `anon` → SELECT only (dashboard read). Tighten with auth if needed.

---

## 4. Webhook ingestion logic (job-requisition.js)

**Endpoint:** `POST /webhook/job-requisition`

1. Reject non-POST. If `WEBHOOK_SECRET` is set, require header
   `X-Webhook-Secret` to match (401 otherwise).
2. Parse JSON. Require `TrackTik Post ID` (400 otherwise).
3. `mapPayloadToRecord()` maps GHL JSON keys → DB columns. **This is an explicit
   allowlist** — a field not listed here is NOT stored. Notable mappings:
   - `"TrackTik Post ID"` → `tracktik_post_id`
   - `"Hiring Manager"` → `hiring_manager` (Title-cased via `toTitleCase`)
   - `"Hiring Needs"` → `hiring_needs` (parsed to int via `toIntOrNull`)
   - `"Operational Job Status"` → `current_status` (lowercased)
4. Upsert `job_requisitions` (insert if new — sets `first_seen_at`,
   `created_at`, `total_cycles=0`; else update, preserving `total_cycles`).
5. Cycle logic:
   - status `open` → reuse an already-open cycle if one exists, else create a
     new cycle (`cycle_number = total_cycles + 1`, `is_open=true`) and bump
     `total_cycles`.
   - status `closed` → find latest open cycle, set `closed_at`, compute
     `days_to_hire`, `is_open=false`, then call `recalculate_pct_time_to_hire`.
6. Insert a `job_status_history` row (status, cycle_number, recorded_at, raw_payload).
7. Return `{ success, tracktik_post_id, status, cycle_number, recorded_at }`.

### The searchable key
`TrackTik Post ID` (e.g. `P00017-UAPTA`) is the unique business identifier. One
Post ID can be opened/closed many times — each open→close pair is a "cycle".

---

## 5. Dashboard metrics (dashboard-data.js)

All cards anchor to the **same date range** (`date_from` / `date_to`, inclusive;
normalized to `T00:00:00.000Z` → `T23:59:59.999Z`). The function fetches jobs +
all their cycles once, then computes each metric in JS:

1. **Opened in Period** — distinct jobs whose `cycle.opened_at` is in range.
2. **Closed in Period** — distinct jobs whose `cycle.closed_at` is in range
   (regardless of when opened).
3. **Total Job Req During Period** — counts **touch-events (cycle rows)**, not
   distinct jobs: a cycle counts if (open & opened ≤ period end) OR opened in
   window OR closed in window. A job closed+reopened in the same window = 2.
4. **Avg Days to Hire** — average `days_to_hire` across the closed cycles in #2's
   period (nulls ignored).
5. **Hiring Need in the Period** — SUM of `hiring_needs` across the **distinct
   jobs** whose cycles touched the window (same set as #3, collapsed to distinct
   `tracktik_post_id` because `hiring_needs` is per-job). Nulls contribute 0.

**Filtering rules worth remembering:**
- Status is applied **cycle-aware** (a job's full cycle history), NOT
  `current_status` — so a closed-then-reopened job appears under both open and
  closed views.
- Filter dropdown options (region, city, hiring_manager, officer_type, site_id)
  are built from **distinct live DB values** — new values appear automatically
  once data exists.

### Region-locked embeddable URLs
`https://<site>.netlify.app/?locked_region=<value>`
- Region dropdown is pre-set, disabled, greyed; a "🔒 Region Locked" badge shows;
  data loads pre-filtered. Matching is case-insensitive substring (`ilike`).
- Region values are whatever GHL sends (e.g. `iowa_region`). Get the exact value
  from the unlocked dashboard's Region dropdown.

---

## 6. Deploy model (how changes go live)

| Change | Action | Goes live |
|---|---|---|
| Frontend (`/public`) | `git push` to `main` | Netlify auto-deploys (~1–2 min) |
| Function (`/netlify/functions`) | `git push` to `main` | Netlify auto-deploys |
| DB schema (column/table/index) | run SQL in Supabase SQL Editor | immediately, independent of code |
| New env variable | add in Netlify → **redeploy** | after redeploy |

- Netlify is wired to the GitHub `main` branch; **every push to `main` is the
  deploy trigger**. No separate build step (`build` is a no-op).
- Supabase is **not** connected to git — schema changes are always manual SQL.
- **Order rule:** if new code reads a new column, run the SQL *before/with* the
  deploy so the live code never queries a missing column.
- Local preview: `netlify dev` (needs the env vars). A raw `file://` open of
  `index.html` won't load `/styles.css` or `/api` — always verify on the
  deployed URL or via `netlify dev`.

### Environment variables (set in Netlify → Site settings → Environment)
| Variable | Used by | Purpose |
|---|---|---|
| `SUPABASE_URL` | all functions | Supabase project URL |
| `SUPABASE_SERVICE_KEY` | all functions | service_role key (full DB access) |
| `WEBHOOK_SECRET` | webhook function | validates inbound GHL requests (`X-Webhook-Secret`) |

---

## 7. FRESH SETUP GUIDE — new client (same features, different GHL)

You've cloned the repo into a new folder. Do this:

### Step 1 — New Supabase project
1. Create a new project at supabase.com (new client = its own DB).
2. SQL Editor → run these files **in order**, each as a new query:
   1. `supabase/schema.sql`
   2. `supabase/migration_001_needs_review.sql`
   3. `supabase/migration_002_cycle_source.sql`
   4. `supabase/migration_003_corrections.sql`
   5. Then run the `hiring_needs` column (not yet saved as a migration file):
      ```sql
      ALTER TABLE job_requisitions
        ADD COLUMN IF NOT EXISTS hiring_needs INTEGER NULL;
      ```
   - **Skip** `correction_001_*`, `cleanup_001_*`, `cleanup_002_*` — those are
     one-time fixes for Citadel's historical data.
3. Settings → API → copy the **Project URL** and the **service_role key**.

> Tip: to guarantee schema parity with Citadel, you can instead restore a
> **schema-only** dump from Citadel (see §8) into the new project, then make sure
> `hiring_needs` exists. Use schema-only so you don't copy Citadel's data.

### Step 2 — New Git repo (optional but recommended)
- Point the new folder at a **new** GitHub repo (new client = separate repo &
  deploy), so pushes don't touch Citadel:
  ```bash
  git remote set-url origin https://github.com/<you>/<new-client-repo>.git
  git push -u origin main
  ```

### Step 3 — New Netlify site
1. Import the new repo. Publish directory = `public` (already in `netlify.toml`).
2. Add environment variables:
   - `SUPABASE_URL` = new project URL
   - `SUPABASE_SERVICE_KEY` = new service_role key
   - `WEBHOOK_SECRET` = a fresh random secret for this client
3. Deploy. Note the site URL, e.g. `https://<new-client>.netlify.app`.

### Step 4 — Configure the client's GHL to send webhooks
(You have their Location ID + API key, but remember: **this app doesn't use the
GHL API** — you're only configuring GHL to push webhooks.)
1. In the client's GHL, on the **Job Requisition** custom object, create a
   workflow/webhook that fires on **Created** and **Updated (status change)**.
2. Webhook URL: `https://<new-client>.netlify.app/webhook/job-requisition`
3. Custom header: `X-Webhook-Secret: <the WEBHOOK_SECRET you set in Netlify>`
4. Ensure the payload includes the same field labels the mapper expects
   (`TrackTik Post ID`, `Operational Job Status`, `Hiring Manager`,
   `Hiring Needs`, `Region`, etc. — see `mapPayloadToRecord` in
   `job-requisition.js`). Field **labels/keys must match**, or they won't be
   stored.

### Step 5 — Test
```bash
curl -X POST https://<new-client>.netlify.app/webhook/job-requisition \
  -H "Content-Type: application/json" \
  -H "X-Webhook-Secret: <your-secret>" \
  -d '{"TrackTik Post ID":"TEST-001","Operational Job Status":"open","Hiring Needs":"2","Region":"test_region"}'
```
Then open the dashboard and confirm the job appears and the cards populate.
(More curl examples are in `DEPLOYMENT.md`.)

### Step 6 — Region-locked embed URLs (if needed)
Read the exact region values from the unlocked dashboard dropdown, then build:
`https://<new-client>.netlify.app/?locked_region=<value>`

### New-client checklist
- [ ] New Supabase project created
- [ ] schema.sql + migration_001/002/003 + hiring_needs ALTER applied
- [ ] correction_/cleanup_ scripts **NOT** run
- [ ] New GitHub repo + remote re-pointed
- [ ] New Netlify site with 3 env vars
- [ ] GHL webhook configured (URL + X-Webhook-Secret, Created & Updated)
- [ ] Payload field labels match the mapper
- [ ] Test webhook lands; dashboard shows data
- [ ] Region lock URLs built from real region values

---

## 8. How to export / copy the Supabase database

(Full step-by-step in the chat answer that accompanies this file. Summary:)

- **Schema only** (recommended for a brand-new client — structure, no Citadel data):
  ```bash
  supabase db dump --db-url "postgresql://postgres:[PASSWORD]@db.[REF].supabase.co:5432/postgres" -f schema_only.sql --schema public
  ```
  (or `pg_dump ... --schema-only`).
- **Full data** (if you ever need to clone Citadel's actual rows): `pg_dump`
  without `--schema-only`, or Supabase Dashboard → Database → Backups.
- Restore into the new project with `psql "<new-db-url>" -f dump.sql`.
- The repo already contains reference dumps in `/supabasebackup/`
  (`full_backup.sql`, `full_backup.dump`, etc.) — Citadel data, for reference.

---

## 9. Project history (change log)

- Core schema, webhook ingestion, dashboard shipped (base README spec).
- CSV import + undo (`import-csv.js`, `undo-import.js`, `import_batches`).
- Admin manual cycle editing (`edit-cycles.js`, `manual_corrections`, migration_003).
- `needs_review` / `review_notes` fields (migration_001).
- `job_cycles.source` ghl|csv (migration_002).
- One-time data fixes: delayed-webhook `opened_at` correction, pre-Apr-2026
  purge, hiring-manager de-duplication (correction_/cleanup_ scripts).
- "Active During Period" card → **"Total Job Req During Period"** (touch-event
  counting); cards reordered.
- Region-lock via `?locked_region=` embeddable URLs.
- **Hiring Needs**: webhook now captures `"Hiring Needs"` → `hiring_needs`
  (int); new summary card **"Hiring Need in the Period"**; value shown in the
  job detail modal's Hiring & Interview section.

---

## 10. Gotchas / things to remember

- **Field mapper is an allowlist** — to capture a new GHL field you must add it
  to `mapPayloadToRecord` AND add the DB column (SQL). One without the other = null.
- **Payload keys must match exactly** (the JSON label GHL sends, not the GHL
  variable name).
- **GHL API key/Location ID are not used in code** — only for configuring GHL's
  webhook side.
- **Supabase pauses** (free tier) can drop webhooks — that's what
  `correction_001` fixed for Citadel. For a production client, keep the project
  active / on a paid tier.
- **RLS**: anon is read-only; all writes go through functions using the
  service_role key. Never expose the service key client-side.
- **`hiring_needs` is per-job** (on `job_requisitions`), so always collapse to
  distinct jobs before summing it (see metric #5).
- Dropdown filter values and region-lock values come straight from live data —
  new regions/managers appear automatically once a job carries them.
