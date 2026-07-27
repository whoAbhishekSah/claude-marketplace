# Frontier Local Testing

Test Frontier locally end-to-end:
- **RPC layer** — ConnectRPC calls with automatic authentication (built-in).
- **UI layer** — drive the **client-demo** and **admin** web apps via [chrome-devtools-mcp](#ui-testing) (button clicks, form fills, navigation), with live SDK rebuilds.
- **GitOps layer** — manage platform users (superadmins), permissions, roles, preferences, and webhooks from a desired-state file with [`frontier reconcile`](#gitops-reconcile). Always dry-run first, show the plan, then ask before applying.

Optionally includes full setup of Frontier with all dependencies. Dependencies (PostgreSQL + SpiceDB) run in **Docker by default** via a provided compose file; a fully-local install is offered as an alternative. Frontier itself is always built from source.

## Configuration

- **Working Directory**: `~/frontier-test` (create if missing)
- **Frontier Source**: Cloned from `https://github.com/raystack/frontier`
- **Proto Definitions**: `~/raystack/proton/raystack/frontier/v1beta1/`
- **Cookie Store**: `~/frontier-test/.cookies.json`
- **Config Store**: `~/frontier-test/.config.json`
- **Generated Frontier Config**: `~/frontier-test/config.yaml`
- **Sample Config Template**: `plugins/frontier-sandbox/config/sample.config.yaml` (in this repo)
- **Sample Desired-State File**: `plugins/frontier-sandbox/config/sample.platform-users.yaml` (in this repo)
- **Desired-State File (user's)**: path stored in `.config.json` under `reconcile_file` — asked once, reused after ([GitOps: reconcile](#gitops-reconcile))
- **Docker Compose File**: `plugins/frontier-sandbox/config/docker-compose.yaml` (in this repo — runs one PG container holding both `frontier` and `frontier_spicedb` DBs, plus a SpiceDB container)

---

## User Interaction Style

For every decision in this skill where the user picks from a fixed set of choices, **use the `AskUserQuestion` tool** rather than printing a prose question and waiting for typed input. The tool renders a radio-button (or multi-select) picker in the UI and returns a structured answer — clearer for the user, no parsing ambiguity for the skill.

Constraints (from the tool itself):
- 1–4 options per question. If the real choice has 5+, group or use multiSelect.
- `preview` (monospace mockup pane) is single-select only.
- Do NOT include an "Other" option — the UI adds one automatically.
- Mark the safest / most common choice with `"(Recommended)"` in the label and put it first.
- For non-mutually-exclusive choices set `multiSelect: true`.

When NOT to use `AskUserQuestion`:
- Free-form values: server address, OTP code, project name, email to log in as, etc. → plain text prompt.
- Pure confirmations during a destructive flow where "Cancel" is the only meaningful alternative — `AskUserQuestion` with two options (e.g. "Proceed" / "Cancel") is still preferred over yes/no prose, because it forces an explicit click.
- Informational messages (no choice required) — just print text.

Throughout the rest of this file, every decision point gives a concrete template. Treat those templates as the canonical wording — keep the questions and option labels stable so users see the same UI for the same decision across sessions.

---

## Startup Behavior

On startup, do NOT print cookies or check env vars.

### Auto-detect Existing Setup

First, check if `~/frontier-test/.config.json` exists. Read `setup_mode` from it (`"docker"` or `"local"`) and check whether the dependencies and Frontier are still up:

**Common to both modes** — check if `frontier_pid` is alive using [Stale PID Detection](#stale-pid-detection).

**If `setup_mode == "docker"`:** check if the dependency containers are running:
```bash
docker ps --filter name=frontier-postgres --filter status=running --format '{{.Names}}'
docker ps --filter name=frontier-spicedb  --filter status=running --format '{{.Names}}'
```

**If `setup_mode == "local"`:** check `spicedb_pid` using [Stale PID Detection](#stale-pid-detection).

Decision:
- **All alive** (deps + Frontier) → greet the user and go straight to [Usage](#usage). Print: `Frontier is running (PID <pid>, port <port>, setup_mode=<mode>). What would you like to test?`
- **Deps alive, Frontier dead** → tell the user dependencies are up and offer to just rebuild/start Frontier
- **Deps dead, Frontier dead** → clean up stale PIDs from `.config.json`, proceed to normal startup flow
- **No setup keys in config** → proceed to normal startup flow

### Normal Startup Flow

Use `AskUserQuestion`:

```
question: "What would you like to do?"
header:   "Action"
multiSelect: false
options:
  - label: "Setup Frontier (Recommended)"
    description: "Start dependencies (PostgreSQL + SpiceDB), build Frontier from source, run migrations, start the server."
  - label: "Skip to testing"
    description: "I already have Frontier running somewhere. Just collect server address + OTP and help me test RPCs."
  - label: "UI only"
    description: "Skip the backend setup. I have Frontier reachable elsewhere — jump straight to building the SDK and launching client-demo or admin via chrome-devtools-mcp."
```

Route by selection:
- "Setup Frontier" → [Environment Setup](#environment-setup)
- "Skip to testing" → [First-time Config](#first-time-config) (collect server address and OTP), then [Usage](#usage)
- "UI only" → [First-time Config](#first-time-config) for server/OTP, then [UI Testing](#ui-testing) path discovery

### Shorthand Commands

At any point during the conversation, recognize these as quick actions — do NOT re-run the startup flow:

| Shorthand | Action |
|-----------|--------|
| **rebuild** / **restart** | [Rebuild & Restart](#rebuild--restart) |
| **logs** / **debug** | [Log Tailing](#log-tailing) |
| **seed** / **populate** | [Seed Data](#seed-data) |
| **reconcile** / **gitops** | [GitOps: reconcile](#gitops-reconcile) — dry run, show plan, ask to apply |
| **dry run** / **plan** | [GitOps: reconcile](#gitops-reconcile), stop after the plan |
| **apply** | [GitOps: reconcile](#gitops-reconcile), skip straight to the apply run (still shows the plan first) |
| **export &lt;kind&gt;** | [Export](#export-seed-a-file-from-the-server) — print live state as a desired-state file |
| **add superadmin &lt;email&gt;** / **make me superadmin** | [Adding a Superadmin](#adding-a-superadmin) |
| **reconcile file** / **change reconcile file** | Re-ask for the desired-state file path and update `reconcile_file` in `.config.json` |
| **status** | [Status Check](#status-check) |
| **teardown** / **stop** / **cleanup** | [Teardown](#teardown) |
| **list rpcs** / **show rpcs** | [Finding Available RPCs](#finding-available-rpcs) |
| **ui** / **open ui** | [UI Testing](#ui-testing) — list apps and pick one |
| **client-demo** / **open client-demo** | Start client-demo, open in browser ([UI Testing](#ui-testing)) |
| **admin** / **open admin** | Start admin app, open in browser ([UI Testing](#ui-testing)) |
| **sdk rebuild** / **rebuild sdk** | Rebuild SDK and refresh running apps ([Rebuild Loop](#rebuild-loop-sdk-changes)) |
| **ui status** | Show ports/PIDs/endpoints for the web apps |
| **ui stop** / **stop ui** | Stop the app dev servers (leaves backend running) |
| **point client-demo to &lt;url&gt;** / **point admin to &lt;url&gt;** | Rewrite the relevant `FRONTIER_*` endpoint key in that app's `.env`, restart |
| **reconfigure** | Re-run [First-time Config](#first-time-config) |

---

## First-time Config

On first run (no `.config.json` exists), ask the user for:

1. **Server address** (default: `localhost:8002`)
2. **Hardcoded OTP** — e.g., `hemlo`

Fixed values (not configurable):
- **Test user domain**: `raystack.org`

Save to `.config.json`:
```json
{
  "server": "localhost:8002",
  "test_domain": "raystack.org",
  "test_otp": "hemlo"
}
```

On subsequent runs, silently load the config. If the user wants to change settings, they can ask to reconfigure.

### Keys the GitOps flow adds

Two more keys get written the first time the user runs a reconcile. Do NOT ask for them during first-time config — they are collected on demand.

| Key | What it is | Set by |
|---|---|---|
| `reconcile_file` | Absolute path to the user's desired-state YAML file | Asked once in [GitOps: reconcile](#gitops-reconcile), reused every run after |
| `bootstrap_client_id` / `bootstrap_client_secret` | The boot-seeded superuser service account from `app.admin.bootstrap` in `config.yaml` | Generated in [Step 5](#step-5-generate-frontier-configyaml), or read back from an existing `config.yaml` |

Both are secrets-adjacent, so `chmod 600 ~/frontier-test/.config.json` after writing (per [File Permissions](#file-permissions)), and never echo the client secret.

---

## Environment Setup

When the user chooses to setup Frontier, first pick a **setup mode**. In both modes, Frontier itself is built from source (so you can iterate on code). Only the dependencies differ.

Use `AskUserQuestion`:

```
question: "How should I run PostgreSQL and SpiceDB?"
header:   "Setup mode"
multiSelect: false
options:
  - label: "Docker (Recommended)"
    description: "Runs PostgreSQL and SpiceDB in containers via the provided docker-compose file. No local install of PG/SpiceDB needed — just Docker and Go 1.24+."
  - label: "Local"
    description: "Installs PostgreSQL 15 and SpiceDB v1.34.0 locally (into ~/frontier-test/bin/, without touching your global setup) and runs them as background processes."
```

Save the chosen value (`"docker"` or `"local"`) under `setup_mode` in `.config.json`.

Then collect the [First-time Config](#first-time-config) values. The additional PG credential questions differ by mode:

**Docker mode** — no PG credential questions. The compose file pins these:
- `pg_user = "frontier"`, `pg_password = "frontier"`, `pg_host = "localhost"`, `pg_port = "5432"`
- `frontier_db = "frontier"`, `spicedb_db = "frontier_spicedb"` (fixed — the container gives isolation, so no random suffix is needed)
- `spicedb_port = 50052`

Just check for port conflicts on the host before starting (see [Port Conflict Detection](#port-conflict-detection)). If `5432` or `50052` is taken, ask the user for alternate host ports and pass them via env vars to docker compose (`PG_PORT=... SPICEDB_GRPC_PORT=...`). Save the chosen values in `.config.json`.

**Local mode** — ask these:
3. **PostgreSQL user** (default: current OS username from `whoami`)
4. **PostgreSQL password** (default: empty — for local trust auth)
5. **PostgreSQL host** (default: `localhost`)
6. **PostgreSQL port** (default: `5432`)

Update `.config.json` with the full set. Example for docker mode:
```json
{
  "server": "localhost:8002",
  "test_domain": "raystack.org",
  "test_otp": "hemlo",
  "setup_mode": "docker",
  "pg_user": "frontier",
  "pg_password": "frontier",
  "pg_host": "localhost",
  "pg_port": "5432",
  "frontier_db": "frontier",
  "spicedb_db": "frontier_spicedb",
  "spicedb_port": 50052
}
```

Example for local mode:
```json
{
  "server": "localhost:8002",
  "test_domain": "raystack.org",
  "test_otp": "hemlo",
  "setup_mode": "local",
  "pg_user": "abhishek",
  "pg_password": "",
  "pg_host": "localhost",
  "pg_port": "5432"
}
```

### Safety Rules

These rules apply to ALL operations throughout this skill. Follow them strictly.

#### Remote Host Protection
If `pg_host` or `server` is **not** `localhost` / `127.0.0.1`, the user is pointing at a remote or shared environment. Before performing any destructive or state-changing action (creating databases, dropping databases, running migrations, starting/stopping services, seeding data), **always ask the user for explicit confirmation** via `AskUserQuestion`:

```
question: "<ACTION_VERB_NOUN> on remote host <host>?"
header:   "Remote action"
multiSelect: false
options:
  - label: "Cancel (Recommended)"
    description: "Don't run this. I'll review the target and re-issue the command myself if I really want it."
  - label: "Proceed"
    description: "Yes, run <ACTION> against <host>. I know this is not localhost and accept the impact."
```

Spell out the exact verb+noun in the question (e.g. "Drop database `frontier_prod` on remote host `db.example.com`?"). Put "Cancel" first as the recommended option — the user has to actively choose to proceed.

Do NOT proceed silently against remote hosts. Do NOT collapse the prompt to a yes/no in prose — the picker keeps the answer auditable.

#### Stale PID Detection
Before killing any process by PID (from `frontier_pid`, `spicedb_pid` in `.config.json`), verify the PID actually belongs to the expected process:
```bash
ps -p <PID> -o comm= 2>/dev/null
```
- For `frontier_pid`, the process name should contain `frontier`
- For `spicedb_pid`, the process name should contain `spicedb`

If the PID doesn't exist or belongs to a different process, do NOT kill it. Warn the user that the stored PID is stale, remove it from `.config.json`, and check if the actual process is still running by port:
```bash
lsof -i :<PORT> -sTCP:LISTEN 2>/dev/null
```

#### Partial Setup Rollback
If setup fails at any step, clean up everything that was created in earlier steps:
- If Frontier build fails (Step 6) → kill SpiceDB process that was started in Step 4
- If Frontier migration fails (Step 7) → kill SpiceDB, optionally drop the databases
- If Frontier fails to start (Step 8) → kill SpiceDB

Before rolling back, tell the user what failed and what will be cleaned up. If the user wants to keep the partial state (e.g., to debug), let them opt out of rollback.

#### Config Backup
Before overwriting `~/frontier-test/config.yaml`, check if it already exists. If it does, back it up:
```bash
cp ~/frontier-test/config.yaml ~/frontier-test/config.yaml.bak.$(date +%s)
```
Tell the user: `Backed up existing config to config.yaml.bak.<timestamp>`

#### Graceful Shutdown
When stopping Frontier or SpiceDB:
1. Send `SIGTERM` first: `kill <PID>`
2. Wait up to 5 seconds for the process to exit: `for i in $(seq 1 10); do kill -0 <PID> 2>/dev/null || break; sleep 0.5; done`
3. Only if it's still running after 5 seconds, send `SIGKILL`: `kill -9 <PID>`
4. Report which signal was needed

Never use `kill -9` as the first action.

#### Never Log Secrets
When showing command output, curl responses, or logs to the user:
- **Strip cookie values** — never show `sid=<actual_value>`, replace with `sid=***`
- **Strip passwords** — never echo the PostgreSQL password from `.config.json`
- **Strip session state tokens** — in auth flow responses, show the structure but mask the `state` value after use

The cookie store file (`.cookies.json`) should never be printed unless the user explicitly asks to see cookies.

#### Health Check Timeout
When waiting for a service to become healthy (SpiceDB in Step 4, Frontier in Step 8):
1. Check every 2 seconds
2. Timeout after **30 seconds**
3. If the service is not healthy after 30 seconds:
   - Show the last 20 lines of the service's log file
   - Tell the user what went wrong
   - Ask via `AskUserQuestion`:

     ```
     question: "<Service> didn't become healthy in 30s. What now?"
     header:   "Health check failed"
     multiSelect: false
     options:
       - label: "Retry (give it another 30s)"
         description: "Some setups boot slowly under load. Re-poll for 30 more seconds."
       - label: "Show more logs"
         description: "Print the last 200 lines of the log file so I can diagnose."
       - label: "Abort & rollback (Recommended)"
         description: "Stop here. Trigger the partial-setup rollback to clean up what was started."
     ```

Do NOT wait indefinitely or retry in a silent loop.

#### File Permissions
When creating or writing files that contain secrets, set permissions to owner-only:
```bash
chmod 600 ~/frontier-test/.cookies.json
chmod 600 ~/frontier-test/.config.json
chmod 600 ~/frontier-test/config.yaml
chmod 600 ~/frontier-test/frontier.log
chmod 600 ~/frontier-test/spicedb.log
```
Apply this after every file creation or write. This prevents other users on the machine from reading session tokens, passwords, or hash keys.

#### Database Name Verification Before Drop
Before dropping any database during teardown:
1. Verify the database name matches the pattern `frontier_<suffix>` or `frontier_spicedb_<suffix>` where `<suffix>` matches the `db_suffix` stored in `.config.json`, **or** matches the fixed docker names (`frontier`, `frontier_spicedb`) when `setup_mode == "docker"`
2. Verify the database actually exists: `psql ... -c "SELECT 1 FROM pg_database WHERE datname = '<db_name>'" 2>/dev/null`
3. If the name doesn't match the expected pattern, refuse to drop and warn the user

---

## Docker Setup Path

Use this path when `setup_mode == "docker"` (the default). It collapses local steps 1–4 (install PG, create DBs, migrate SpiceDB, start SpiceDB) into a single `docker compose up`, because the compose file ships everything needed.

### Docker Prerequisites

**Check**: `docker --version` and `docker compose version` (or `docker-compose --version`). Also run `docker info` to confirm the Docker daemon is actually reachable.

- If Docker isn't installed or the daemon isn't running, **stop and tell the user**. Do NOT try to `brew install docker` silently — Docker Desktop / Colima / OrbStack is a user-level install choice. Ask via `AskUserQuestion`:

  ```
  question: "Docker isn't running. How do you want to proceed?"
  header:   "Docker missing"
  multiSelect: false
  options:
    - label: "Retry — I just started Docker"
      description: "Re-run the docker daemon check. Pick this after starting Docker Desktop / Colima / OrbStack."
    - label: "Fall back to local mode"
      description: "Rerun setup with setup_mode = local — installs PostgreSQL 15 and SpiceDB v1.34.0 into ~/frontier-test/bin/."
    - label: "Cancel"
      description: "Stop setup. I'll install Docker myself and re-run later."
  ```

- **Go >= 1.24.0** is still required to build Frontier from source. Use the same check/install logic as [Go >= 1.24.0](#3-go--1240) below.

Docker mode does NOT need local `psql`/`createdb`/`dropdb`/`spicedb` binaries. All DB work happens through the postgres container via `docker exec` or short-lived `psql` invocations inside the container.

### Docker Step 1: Start dependencies

The compose file is at `plugins/frontier-sandbox/config/docker-compose.yaml`. Locate the repo root — if the plugin was installed through `/plugin install`, the path looks like `~/.claude/plugins/<marketplace>/frontier-sandbox/config/docker-compose.yaml`. Store the resolved path in `.config.json` as `compose_file`.

Start the stack:
```bash
docker compose -f <compose_file> -p frontier-sandbox up -d
```

If the user picked non-default ports, pass them as env vars:
```bash
PG_PORT=<pg_port> SPICEDB_GRPC_PORT=<spicedb_port> \
  docker compose -f <compose_file> -p frontier-sandbox up -d
```

**Wait for readiness** (apply [Health Check Timeout](#health-check-timeout) — 30s cap, show logs on failure):
- Postgres: `docker exec frontier-postgres pg_isready -U frontier -d frontier` returns 0
- SpiceDB migrate container has exited successfully: `docker inspect -f '{{.State.ExitCode}}' frontier-spicedb-migrate` returns `0`
- SpiceDB serve container is running: `docker inspect -f '{{.State.Running}}' frontier-spicedb` returns `true`, and the gRPC port is listening on the host

The compose file creates both databases automatically:
- `frontier` — via `POSTGRES_DB` env var
- `frontier_spicedb` — via the `init-db.sql` script mounted into `/docker-entrypoint-initdb.d/`

If migration logs show errors, fetch them with `docker logs frontier-spicedb-migrate` and surface to the user.

### Docker Step 2: Verify DB connectivity from host

Confirm that the host can reach the containerized PG on the published port:
```bash
psql "postgres://frontier:frontier@localhost:<pg_port>/frontier?sslmode=disable" -c "SELECT 1;"
```

If `psql` isn't on the host, run the check *inside* the container instead:
```bash
docker exec frontier-postgres psql -U frontier -d frontier -c "SELECT 1;"
```

After this succeeds, jump to [Step 5: Generate Frontier config.yaml](#step-5-generate-frontier-configyaml) and continue with Steps 5–8 (they're identical for both modes).

---

## Local Setup Path

Use this path when `setup_mode == "local"`. Follow Prerequisites Check → Steps 1–8.

### Prerequisites Check

Local binary directory: `~/frontier-test/bin/` (create if missing).

Check each dependency in order. If the right version is already on the system, use it. If not, install it **locally** into `~/frontier-test/bin/` — never touch the global installation. Tell the user what was installed and where.

Store the resolved binary paths in `.config.json` so all subsequent commands use the correct versions:
```json
{
  "bin_psql": "/opt/homebrew/opt/postgresql@15/bin/psql",
  "bin_createdb": "/opt/homebrew/opt/postgresql@15/bin/createdb",
  "bin_dropdb": "/opt/homebrew/opt/postgresql@15/bin/dropdb",
  "bin_spicedb": "~/frontier-test/bin/spicedb",
  "bin_go": "~/frontier-test/bin/go1.24.0",
  "pg_data_dir": "~/frontier-test/pgdata"
}
```

All commands in this skill (createdb, dropdb, psql, spicedb, go build, etc.) MUST use the resolved binary path from `.config.json`, never bare command names.

#### 1. PostgreSQL 15

**Check**: `psql --version` — look for `15.x`.

If PostgreSQL 15 is already running locally and accessible, use it. Store the path to `psql`/`createdb`/`dropdb` in `.config.json`.

**If not found or wrong version**, install locally:
```bash
brew install postgresql@15
```
This installs without linking, so it won't conflict with any existing PostgreSQL. Binaries are at `/opt/homebrew/opt/postgresql@15/bin/` (Apple Silicon) or `/usr/local/opt/postgresql@15/bin/` (Intel).

If no PostgreSQL server is running on the expected port, start a **local instance** with its own data directory:
```bash
mkdir -p ~/frontier-test/pgdata
/opt/homebrew/opt/postgresql@15/bin/initdb -D ~/frontier-test/pgdata
/opt/homebrew/opt/postgresql@15/bin/pg_ctl -D ~/frontier-test/pgdata -l ~/frontier-test/pg.log -o "-p <PG_PORT>" start
```
Store the data dir in `.config.json` under `"pg_data_dir"` so teardown can stop it.

Tell the user: `Installed PostgreSQL 15 locally. Binaries at /opt/homebrew/opt/postgresql@15/bin/, data at ~/frontier-test/pgdata`

#### 2. SpiceDB v1.34.0

**Check**: `spicedb version` — look for exactly `v1.34.0`.

If found, use it. Store path in `.config.json`.

**If not found or wrong version**, download the specific release:
```bash
mkdir -p ~/frontier-test/bin
# macOS ARM
curl -L -o ~/frontier-test/bin/spicedb.tar.gz \
  "https://github.com/authzed/spicedb/releases/download/v1.34.0/spicedb_1.34.0_darwin_arm64.tar.gz"
# macOS Intel — use darwin_amd64 instead

tar -xzf ~/frontier-test/bin/spicedb.tar.gz -C ~/frontier-test/bin/ spicedb
rm ~/frontier-test/bin/spicedb.tar.gz
chmod +x ~/frontier-test/bin/spicedb
```

Detect architecture with `uname -m` (`arm64` = Apple Silicon, `x86_64` = Intel).

Tell the user: `Installed SpiceDB v1.34.0 locally at ~/frontier-test/bin/spicedb`

#### 3. Go >= 1.24.0

**Check**: `go version` — look for `1.24.0` or higher.

If found, use it. Store path in `.config.json`.

**If not found or wrong version**, install using Go's version manager:
```bash
# Use existing go (any version) to download the right one
go install golang.org/dl/go1.24.0@latest
go1.24.0 download
# The binary is at ~/go/bin/go1.24.0
ln -sf ~/go/bin/go1.24.0 ~/frontier-test/bin/go1.24.0
```

If no `go` exists at all:
```bash
brew install go
go install golang.org/dl/go1.24.0@latest
go1.24.0 download
ln -sf ~/go/bin/go1.24.0 ~/frontier-test/bin/go1.24.0
```

Tell the user: `Installed Go 1.24.0 locally at ~/frontier-test/bin/go1.24.0`

#### Summary

After all checks, print a summary:
```
Prerequisites:
  PostgreSQL 15  ✓ (system)     /opt/homebrew/bin/psql
  SpiceDB 1.34.0 ✓ (installed)  ~/frontier-test/bin/spicedb
  Go 1.24.0      ✓ (system)     /opt/homebrew/bin/go
```

### Port Conflict Detection

Before starting any services, check if the required ports are already in use:

```bash
lsof -i :8002 -sTCP:LISTEN 2>/dev/null   # Frontier ConnectRPC
lsof -i :50052 -sTCP:LISTEN 2>/dev/null   # SpiceDB gRPC
lsof -i :9000 -sTCP:LISTEN 2>/dev/null    # Frontier metrics
```

If any port is occupied:
1. Show the user which port is in use and which process holds it (PID, process name)
2. Ask via `AskUserQuestion`:

   ```
   question: "Port <PORT> is in use by PID <PID> (<process>). How should I proceed?"
   header:   "Port conflict"
   multiSelect: false
   options:
     - label: "Kill the existing process"
       description: "Send SIGTERM (then SIGKILL after 5s) to PID <PID>. Choose this if it looks like a stale Frontier/SpiceDB from a previous run."
     - label: "Use alternate ports (Recommended)"
       description: "Pick free ports for Frontier/SpiceDB/metrics and update .config.json + config.yaml accordingly. Safer if you're not sure what's holding the port."
     - label: "Cancel setup"
       description: "Stop here. I'll investigate the conflict myself and re-run setup later."
   ```

3. Do NOT silently fail or overwrite a running service. If the user picks "Use alternate ports", prompt with free-text input for the new port number(s), then update `spicedb_port` in `.config.json` and `app.connect.port` / `spicedb.port` / `app.metrics_port` in the generated config.yaml.

### Resume After Failure

Before running each step, check if it was already completed in a previous run. This lets users resume without redoing everything:

| Step | How to detect already done |
|------|---------------------------|
| Docker Step 1 (containers up) | `docker ps --filter name=frontier-postgres --filter status=running -q` is non-empty AND same for `frontier-spicedb`. If containers exist but are stopped, `docker compose ... start` instead of recreating |
| Docker Step 2 (DB connectivity) | Always re-check — it's fast |
| Local Step 1 (DB connectivity) | Always re-check — it's fast |
| Local Step 2 (Create databases) | Check if `frontier_db` and `spicedb_db` from `.config.json` exist: `psql ... -c "SELECT 1 FROM pg_database WHERE datname='<db>'"` |
| Local Step 3 (SpiceDB migrate) | Check if SpiceDB tables exist in the database: `psql <spicedb_db> -c "SELECT 1 FROM information_schema.tables WHERE table_name='relation_tuple'" 2>/dev/null` |
| Local Step 4 (SpiceDB running) | Check if `spicedb_pid` is alive or if the SpiceDB port is listening |
| Step 5 (Config generated) | Check if `~/frontier-test/config.yaml` exists |
| Step 6 (Frontier built) | Check if `~/frontier-test/frontier` binary exists AND `source_git_hash` in `.config.json` matches current `git rev-parse HEAD` in `~/raystack/frontier` |
| Step 7 (Frontier migrate) | Check if Frontier tables exist: `psql <frontier_db> -c "SELECT 1 FROM information_schema.tables WHERE table_name='users'" 2>/dev/null` |
| Step 8 (Frontier running) | Check if `frontier_pid` is alive or if the Frontier port is listening |

If a step is already done, print `Step N: <description> — already done, skipping` and move on.

### Progress Messages

For steps that take noticeable time, print a message BEFORE starting so the user knows what's happening:

| Step | Message |
|------|---------|
| Step 2 | `Creating databases frontier_<suffix> and frontier_spicedb_<suffix>...` |
| Step 3 | `Running SpiceDB migrations...` |
| Step 4 | `Starting SpiceDB on port <port>...` |
| Step 5 | `Generating Frontier config...` |
| Step 6 | `Building Frontier from source... this may take a few minutes on first run` |
| Step 7 | `Running Frontier database migrations...` |
| Step 8 | `Starting Frontier on port <port>...` |

After each step succeeds, print a short confirmation: `Done.` or `SpiceDB is healthy.` etc.

### Step 1: Verify PostgreSQL Connectivity

Before creating databases or running migrations, verify that the configured PostgreSQL credentials actually work:

```bash
psql "postgres://<PG_USER>:<PG_PASSWORD>@<PG_HOST>:<PG_PORT>/postgres?sslmode=disable" -c "SELECT 1;"
```

If the password is empty, use `postgres://<PG_USER>:@<PG_HOST>:<PG_PORT>/postgres?sslmode=disable`.

**If this fails**, stop immediately and tell the user:
- What the error was (auth failure, connection refused, etc.)
- Ask them to provide corrected PostgreSQL credentials
- Do NOT proceed with database creation or migrations

### Step 2: Create PostgreSQL Databases

Generate a **short random suffix** (e.g., 4 hex chars like `a3f1`) to avoid collisions with existing databases:

```bash
SUFFIX=$(openssl rand -hex 2)
```

Create two databases using the verified credentials:
```bash
createdb -U <PG_USER> -h <PG_HOST> -p <PG_PORT> "frontier_spicedb_${SUFFIX}"
createdb -U <PG_USER> -h <PG_HOST> -p <PG_PORT> "frontier_${SUFFIX}"
```

If the user has a password, set `PGPASSWORD` env var before running createdb.

Update `.config.json` with the database details:
```json
{
  "db_suffix": "a3f1",
  "frontier_db": "frontier_a3f1",
  "spicedb_db": "frontier_spicedb_a3f1",
  "spicedb_port": 50052
}
```

### Step 3: Migrate SpiceDB

Build the connection URI using configured credentials. If password is non-empty, include it:
- With password: `postgres://<PG_USER>:<PG_PASSWORD>@<PG_HOST>:<PG_PORT>/frontier_spicedb_<SUFFIX>?sslmode=disable`
- Without password: `postgres://<PG_USER>:@<PG_HOST>:<PG_PORT>/frontier_spicedb_<SUFFIX>?sslmode=disable`

```bash
spicedb migrate head \
    --datastore-engine postgres \
    --datastore-conn-uri "<CONN_URI>"
```

### Step 4: Start SpiceDB in Background

```bash
spicedb serve \
    --grpc-preshared-key "frontier" \
    --datastore-engine postgres \
    --datastore-conn-uri "<CONN_URI_FOR_SPICEDB_DB>" \
    --http-enabled \
    --grpc-addr :50052
```

Run this as a background process. Store the PID in `.config.json` under `"spicedb_pid"` so it can be stopped later.

Wait a few seconds and verify SpiceDB is healthy before proceeding (check that the gRPC port is listening).

---

## Shared Steps (Both Modes)

Steps 5–8 are identical for docker and local setups — they build and run Frontier from source against whatever dependencies were started.

### Step 5: Generate Frontier config.yaml

Copy the **sample config template** from `plugins/frontier-sandbox/config/sample.config.yaml` in this repo to `~/frontier-test/config.yaml`.

Replace the placeholders with actual values:
- `<HASH_SECRET_KEY>` — generate a random 32-char hex string: `openssl rand -hex 16`
- `<BLOCK_SECRET_KEY>` — generate a different random 32-char hex string: `openssl rand -hex 16`
- `<TEST_OTP>` — from `.config.json`
- `<PG_USER>` — from `.config.json` (`"frontier"` in docker mode)
- `<PG_PASSWORD>` — from `.config.json` (`"frontier"` in docker mode; empty string for local trust auth)
- `<PG_HOST>` — from `.config.json` (`"localhost"` — docker publishes the container port to the host)
- `<PG_PORT>` — from `.config.json`
- `<FRONTIER_DB>` — e.g., `frontier_a3f1` (local) or `frontier` (docker)
- `<SPICEDB_PORT>` — from `.config.json`
- `<BOOTSTRAP_CLIENT_ID>` — generate a UUID: `uuidgen | tr 'A-Z' 'a-z'` (the server rejects a non-UUID here)
- `<BOOTSTRAP_CLIENT_SECRET>` — generate a random 64-char hex string: `openssl rand -hex 32`

Do NOT hardcode the secret keys. Generate fresh ones each setup.

**Save the bootstrap pair.** Write `bootstrap_client_id` and `bootstrap_client_secret` into `.config.json` right after generating them. Every `frontier reconcile` and `frontier export` run needs them ([GitOps: reconcile](#gitops-reconcile)). If `config.yaml` already exists and has an `app.admin.bootstrap` block, read the pair back out of it instead of generating a new one — changing the secret rotates the credential on the next boot.

**There is no `app.admin.users` list anymore.** The server dropped it (RFC 0001). If a config template still has one, delete it — leaving it in does nothing and misleads the next reader. Superadmins now come only from the bootstrap service account plus whatever the reconcile file grants.

### Step 6: Clone and Build Frontier

If Frontier source is not already present at `~/raystack/frontier`, clone it:
```bash
git clone https://github.com/raystack/frontier ~/raystack/frontier
```

If Proton (proto definitions) is not already present at `~/raystack/proton`, clone it for RPC discovery:
```bash
git clone https://github.com/raystack/proton ~/raystack/proton
```

**Build cache**: Before building, check if a rebuild is actually needed:
```bash
CURRENT_HASH=$(cd ~/raystack/frontier && git rev-parse HEAD)
STORED_HASH=$(cat .config.json | grep source_git_hash | ... )  # read from .config.json
```
- If `source_git_hash` in `.config.json` matches `CURRENT_HASH` AND `~/frontier-test/frontier` binary exists, skip the build: `Build skipped — source unchanged (commit <short_hash>)`
- Otherwise, build and store the new hash:

```bash
cd ~/raystack/frontier && CGO_ENABLED=0 go build -o ~/frontier-test/frontier .
```
After a successful build, update `.config.json` with `"source_git_hash": "<CURRENT_HASH>"`.

### Step 7: Migrate Frontier Database

```bash
~/frontier-test/frontier server migrate -c ~/frontier-test/config.yaml
```

### Step 8: Start Frontier in Background

```bash
~/frontier-test/frontier server start -c ~/frontier-test/config.yaml
```

Run as a background process. Store the PID in `.config.json` under `"frontier_pid"`.

Wait a few seconds and verify Frontier is healthy by hitting:
```bash
curl -s http://localhost:8002/raystack.frontier.v1beta1.FrontierService/ListUsers \
  -H "connect-protocol-version: 1" \
  -H "content-type: application/json" \
  -d '{}'
```

If it returns a response (even an auth error), the server is running.

### Step 9: Create the First Superadmins

A fresh server has exactly one superuser: the bootstrap service account. No human email is a superadmin until a reconcile run makes one — the `+sa` suffix by itself grants nothing now.

Ask via `AskUserQuestion`:

```
question: "No human superadmin exists yet. Create one now?"
header:   "Superadmin"
multiSelect: false
options:
  - label: "Yes — use the sample file (Recommended)"
    description: "Copy plugins/frontier-sandbox/config/sample.platform-users.yaml to ~/frontier-test/platform-users.yaml and reconcile it. Grants admin1+sa@raystack.org and admin2+sa@raystack.org."
  - label: "Yes — I have my own file"
    description: "Point me at an existing desired-state YAML file and reconcile that instead."
  - label: "Skip for now"
    description: "Leave the bootstrap service account as the only superuser. AdminService calls will need Basic auth until you run a reconcile."
```

Then run [GitOps: reconcile](#gitops-reconcile) with the chosen file. Store the path under `reconcile_file`.

### Setup Complete — Quick Reference

After all steps succeed, print this summary. The SpiceDB line reads "(docker)" or "(PID ...)" depending on mode:

```
Frontier is ready!  [setup_mode: <docker|local>]

  Frontier:    http://localhost:<port> (PID <pid>)
  SpiceDB:     localhost:<spicedb_port> <(docker) | (PID <pid>)>
  Postgres:    localhost:<pg_port> <(docker) | (local)>
  Frontier DB: <frontier_db>
  SpiceDB DB:  <spicedb_db>

Things to try:
  "list all users as admin"
  "create an org called my-org"
  "reconcile" — dry-run the desired-state file, then apply it
  "export platformuser" — dump current superadmins as a file
  "add superadmin me+sa@raystack.org"
  "seed" — create sample orgs, users, and projects
  "show me available RPCs"
  "logs" — view server logs
  "status" — check what's running
  "rebuild" — rebuild after code changes
  "teardown" — stop everything

UI testing (see "UI Testing" section):
  "open client-demo"  / "open admin"  — launch in browser
  "sdk rebuild"       — pick up SDK changes
  "ui status"         — what's running on the web side
  "point client-demo to <url>" — repoint an app at a different Frontier
```

### Teardown

When the user asks to **stop**, **teardown**, or **cleanup** the environment, branch on `setup_mode` in `.config.json`:

**Common first step (both modes):** Kill the Frontier process using stored `frontier_pid` (apply [Graceful Shutdown](#graceful-shutdown) and [Stale PID Detection](#stale-pid-detection)).

**If `setup_mode == "docker"`:**
1. Ask via `AskUserQuestion`:

   ```
   question: "Teardown mode for docker setup?"
   header:   "Teardown"
   multiSelect: false
   options:
     - label: "Stop only (Recommended)"
       description: "Containers down, volume kept (data survives). Same as `docker compose down`. Use when you want to resume later with the same DB state."
     - label: "Full cleanup"
       description: "Drops the persistent volume — both databases go with it. Same as `docker compose down -v`. Use when you want a clean slate next time."
     - label: "Cancel"
       description: "Don't touch the containers. Leave everything running."
   ```

2. Remove `frontier_pid` and setup container keys from `.config.json` (keep `setup_mode` so the next run remembers the choice, unless the user asks to reconfigure).

**If `setup_mode == "local"`:**
1. Kill SpiceDB process (using stored `spicedb_pid`)
2. If a local PostgreSQL was started (`pg_data_dir` exists in `.config.json`), stop it:
   ```bash
   <bin_pg_ctl> -D ~/frontier-test/pgdata stop
   ```
3. Optionally drop the databases (use resolved `bin_dropdb` path, apply [Database Name Verification Before Drop](#database-name-verification-before-drop)):
   ```bash
   <bin_dropdb> -U <PG_USER> -h <PG_HOST> -p <PG_PORT> "frontier_<SUFFIX>"
   <bin_dropdb> -U <PG_USER> -h <PG_HOST> -p <PG_PORT> "frontier_spicedb_<SUFFIX>"
   ```
4. Clean up `.config.json` by removing the setup-related keys

Always confirm with the user before dropping data or databases.

### Status Check

When the user asks for **status**, branch on `setup_mode`:

**Both modes:** Check if the Frontier process is running (stored `frontier_pid`), and whether the Frontier HTTP port responds to a quick `curl`.

**If `setup_mode == "docker"`:**
- `docker ps --filter label=com.docker.compose.project=frontier-sandbox --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'`
- Verify Postgres is accepting connections: `docker exec frontier-postgres pg_isready -U frontier -d frontier`

**If `setup_mode == "local"`:**
- Check if SpiceDB process is running (using stored PID)
- Check if PostgreSQL is accepting connections via `psql ... -c "SELECT 1"`

Report database names, ports, PIDs, and (for docker) container health.

### Rebuild & Restart

When the user asks to **rebuild**, **restart**, or says they **changed code**:

1. Rebuild the Frontier binary from source:
   ```bash
   cd ~/raystack/frontier && CGO_ENABLED=0 go build -o ~/frontier-test/frontier .
   ```
2. If the build fails, show the error and stop — do NOT kill the running server
3. If the build succeeds:
   - Kill the existing Frontier process (using stored `frontier_pid`)
   - Wait for the port to be free: `while lsof -i :8002 -sTCP:LISTEN >/dev/null 2>&1; do sleep 0.5; done`
   - Start the new binary: `~/frontier-test/frontier server start -c ~/frontier-test/config.yaml`
   - Store the new PID in `.config.json`
   - Verify it's healthy with a curl check
4. Do NOT restart SpiceDB or re-run migrations — only the Frontier process is affected

If the user says **migrate and restart** or mentions schema changes, also run:
```bash
~/frontier-test/frontier server migrate -c ~/frontier-test/config.yaml
```
before starting the server.

### Log Tailing

When the user asks for **logs**, wants to **debug** a failed request, or asks **what went wrong**:

Frontier and SpiceDB are started as background processes. Their stdout/stderr are captured in log files:

- **Frontier logs**: `~/frontier-test/frontier.log`
- **SpiceDB logs**: `~/frontier-test/spicedb.log`

When starting services in background (Steps 4 and 8), redirect output to these files:
```bash
# SpiceDB (Step 4)
spicedb serve ... > ~/frontier-test/spicedb.log 2>&1 &

# Frontier (Step 8)
~/frontier-test/frontier server start -c ~/frontier-test/config.yaml > ~/frontier-test/frontier.log 2>&1 &
```

To show logs:
```bash
# Last 50 lines of Frontier logs
tail -50 ~/frontier-test/frontier.log

# Last 50 lines of SpiceDB logs
tail -50 ~/frontier-test/spicedb.log
```

When the user asks about a specific error or failed RPC:
1. Read the last 50 lines of Frontier logs
2. Look for error messages, stack traces, or the relevant RPC name
3. Summarize what went wrong in plain language

### Seed Data

When the user asks to **seed**, **populate**, or wants **sample data** to work with, create a standard test environment using RPC calls:

**Step 1: Authenticate as superadmin**
Login as a reconciled platform admin (e.g. `admin1+sa@raystack.org`) using the auto-login flow. If that email is not in the reconcile file yet, it has no AdminService access — run [Adding a Superadmin](#adding-a-superadmin) first, or fall back to [Bootstrap Service Account Auth](#bootstrap-service-account-auth).

**Step 2: Create test organizations**
```bash
# Create two orgs
curl -s -X POST "http://<SERVER>/raystack.frontier.v1beta1.FrontierService/CreateOrganization" \
  -H "connect-protocol-version: 1" \
  -H "content-type: application/json" \
  -H "Cookie: sid=<ADMIN_TOKEN>" \
  -d '{"body":{"name":"org-alpha","title":"Alpha Organization"}}'

curl -s -X POST "http://<SERVER>/raystack.frontier.v1beta1.FrontierService/CreateOrganization" \
  -H "connect-protocol-version: 1" \
  -H "content-type: application/json" \
  -H "Cookie: sid=<ADMIN_TOKEN>" \
  -d '{"body":{"name":"org-beta","title":"Beta Organization"}}'
```

**Step 3: Create test users by logging them in**
Login as each user to auto-create their accounts:
- `alice@raystack.org` — will be org admin
- `bob@raystack.org` — will be org member
- `charlie@raystack.org` — will be viewer

**Step 4: Create projects**
```bash
curl -s -X POST "http://<SERVER>/raystack.frontier.v1beta1.FrontierService/CreateProject" \
  -H "connect-protocol-version: 1" \
  -H "content-type: application/json" \
  -H "Cookie: sid=<ADMIN_TOKEN>" \
  -d '{"body":{"name":"project-atlas","title":"Atlas Project","orgId":"<ORG_ALPHA_ID>"}}'
```

**Step 5: Report what was created**
After seeding, print a summary table:
```
Seed data created:
  Organizations: org-alpha, org-beta
  Users: alice@raystack.org, bob@raystack.org, charlie@raystack.org
  Projects: project-atlas (under org-alpha)
  Admin: admin1+sa@raystack.org
```

The user can ask to seed at any time. If any item already exists (org name conflict, project name conflict), ask via `AskUserQuestion` instead of silently deciding:

```
question: "Some seed items already exist. How should I handle conflicts?"
header:   "Seed conflict"
multiSelect: false
options:
  - label: "Skip existing (Recommended)"
    description: "Leave existing items alone, only create the ones that don't exist. Safe default."
  - label: "Use unique suffix"
    description: "Append a short random suffix to conflicting names (e.g. org-alpha-a3f1) so everything gets created fresh alongside the existing data."
  - label: "Abort seed"
    description: "Stop. I'll clean up myself and re-run seed once the existing items are gone."
```

After seeding, print the summary table listing exactly which items were created vs skipped vs suffixed.

---

## Services

| Service | ConnectRPC Path |
|---------|-----------------|
| **FrontierService** | `raystack.frontier.v1beta1.FrontierService/<RPC_NAME>` |
| **AdminService** | `raystack.frontier.v1beta1.AdminService/<RPC_NAME>` |

## Authentication

### Cookie Store

Cookies are persisted in `~/frontier-test/.cookies.json` as a JSON object mapping email to sid value:

```json
{
  "user@raystack.org": "session-id-abc",
  "user+sa@raystack.org": "session-id-xyz"
}
```

- On startup, silently read the cookie store file (create if missing)
- When making a request, check if a valid cookie exists for the user
- If a request fails with auth error (unauthenticated), re-authenticate and retry
- Never print cookie values to the user unless explicitly asked

### Automatic Login (mailotp flow)

When a cookie is needed for a user and none exists (or expired), authenticate automatically:

**Step 1: Call Authenticate**
```bash
curl -s -X POST "http://<SERVER>/raystack.frontier.v1beta1.FrontierService/Authenticate" \
  -H "connect-protocol-version: 1" \
  -H "content-type: application/json" \
  -d '{"strategyName":"mailotp","email":"<EMAIL>","callbackUrl":"http://<SERVER>/callback"}'
```
Replace `<SERVER>` with the configured server address. Extract `state` from the JSON response.

**Step 2: Get the OTP code**

Use the configured `test_otp` from `.config.json`. Only emails on `raystack.org` are supported for auto-login.

**Step 3: Call AuthCallback and extract cookie**
```bash
curl -s -v -X POST "http://<SERVER>/raystack.frontier.v1beta1.FrontierService/AuthCallback" \
  -H "connect-protocol-version: 1" \
  -H "content-type: application/json" \
  -d '{"strategyName":"mailotp","state":"<STATE>","code":"<OTP>"}' 2>&1
```
Extract the `sid=` value from the `Set-Cookie` response header. Store it in the cookie store file.

### Test Users

Emails on `raystack.org` use the hardcoded OTP. No database access needed.

- `user1@raystack.org` / `user2@raystack.org` / etc. — regular users
- `user1+sa@raystack.org` — the naming convention for an intended super admin. It only *is* one after a reconcile run grants it `relation: admin` (see [Super Admin vs Org Admin](#super-admin-vs-org-admin)).

**Only raystack.org users are supported for auto-login.** For real users, provide a cookie manually.

### Super Admin vs Org Admin

There are two kinds of "admin" in Frontier — don't confuse them:

- **Super admin** (platform-level): Granted by a `PlatformUser` entry with `relation: admin`. Has access to both FrontierService and AdminService.
- **Org admin** (org-level): A regular user who has been granted an admin/owner role within a specific organization. Can manage that org via FrontierService but has NO AdminService access.

#### How super admins are made now (this changed)

Older versions promoted every email in `app.admin.users` in `config.yaml` at boot. **That is gone.** The server no longer reads that key. Two things replaced it:

1. **The bootstrap service account** — `app.admin.bootstrap` in `config.yaml`. One service account, seeded at every boot, always a superuser. It exists so automation has somewhere to start. It authenticates with Basic auth, not a cookie.
2. **The `PlatformUser` kind** — every other superadmin (human or service) comes from a desired-state file applied with `frontier reconcile`. See [GitOps: reconcile](#gitops-reconcile).

Practical consequences for this skill:

- **The `+sa` suffix is now just a naming convention.** `admin1+sa@raystack.org` is an ordinary user until a reconcile run grants it `relation: admin`. Logging in with a `+sa` email does NOT give AdminService access on its own.
- **A fresh server has no human superadmin.** If an AdminService call fails with a permission error, the first thing to check is whether that email is in the reconcile file.
- If the user says "log in as super admin" and no reconciled admin exists yet, offer [Adding a Superadmin](#adding-a-superadmin) rather than just picking a `+sa` email and hoping.

### Cookie Rules

| Credential | FrontierService | AdminService |
|-------------|-----------------|--------------|
| Cookie for a user with `relation: admin` in the reconcile file | Yes | Yes |
| Cookie for any other user (including an unreconciled `+sa` email) | Yes | No |
| Basic auth with the bootstrap service account | Yes | Yes |

- AdminService requests need a **platform admin**. That is either a reconciled `PlatformUser` cookie or the bootstrap service account's Basic auth header.
- If the user asks to call AdminService without saying who to act as, ask. Offer the reconciled admins from `reconcile_file` as the options.
- The cookie store and the mailotp auto-login flow are unchanged — they still work exactly as documented above. Only *who counts as a superadmin* changed.

### Bootstrap Service Account Auth

The bootstrap account uses HTTP Basic auth, not a session cookie. Build the header from `.config.json`:

```bash
BASIC=$(printf '%s:%s' "<bootstrap_client_id>" "<bootstrap_client_secret>" | base64)
```

Use it in a curl call:
```bash
curl -s -X POST "http://<SERVER>/raystack.frontier.v1beta1.AdminService/<RPC_NAME>" \
  -H "connect-protocol-version: 1" \
  -H "content-type: application/json" \
  -H "Authorization: Basic ${BASIC}" \
  -d '<JSON_BODY>'
```

Never print `$BASIC` or the client secret — it is a permanent superuser credential, not a session token. Mask it as `Basic ***` in anything you show the user (per [Never Log Secrets](#never-log-secrets)).

Prefer a reconciled human cookie for day-to-day testing. Use the bootstrap account when there is no human superadmin yet, or for the reconcile and export commands themselves.

## Usage

When the user wants to test an RPC:

1. Determine which email/user identity to use:
   - If the user specifies an email, use that
   - If context makes it clear (e.g., "as super admin" or "as admin1+sa"), use the appropriate stored cookie
   - If unclear, ask which user to act as
2. Check the cookie store for a valid session for that email
3. If no cookie exists, run the auto-login flow silently and store the cookie
4. Make the RPC call
5. If auth fails, re-login and retry once

## ConnectRPC Curl Template

```bash
curl -s -X POST "http://<SERVER>/raystack.frontier.v1beta1.<SERVICE>Service/<RPC_NAME>" \
  -H "connect-protocol-version: 1" \
  -H "content-type: application/json" \
  -H "Cookie: sid=<TOKEN>" \
  -d '<JSON_BODY>'
```

Replace `<SERVER>` with the configured server address.

## Finding Available RPCs

When the user asks to **list RPCs**, **find an RPC**, or asks **what RPCs are available**:

### List RPCs

```bash
# List all RPCs in FrontierService
grep -E "^\s+rpc " ~/raystack/proton/raystack/frontier/v1beta1/frontier.proto

# List all RPCs in AdminService
grep -E "^\s+rpc " ~/raystack/proton/raystack/frontier/v1beta1/admin.proto
```

### Proto-Aware RPC Discovery

When the user asks about a **specific RPC** or wants to know **what fields to pass**, go deeper:

1. Find the RPC definition and extract the request/response message names:
   ```bash
   grep -E "rpc <RPC_NAME>" ~/raystack/proton/raystack/frontier/v1beta1/frontier.proto
   ```
   This gives e.g. `rpc CreateOrganization(CreateOrganizationRequest) returns (CreateOrganizationResponse)`

2. Find the request message definition and show its fields:
   ```bash
   # Search across all proto files in the frontier v1beta1 directory
   grep -A 20 "message <RequestMessageName> {" ~/raystack/proton/raystack/frontier/v1beta1/*.proto
   ```

3. If a field references another message type (e.g., `OrganizationRequestBody body = 1`), recursively look up that message too.

4. Present the information as a formatted summary, for example:
   ```
   CreateOrganization
     Service: FrontierService
     Request: CreateOrganizationRequest
       - body (OrganizationRequestBody, required):
           - name (string)
           - title (string)
           - metadata (google.protobuf.Struct)
     Response: CreateOrganizationResponse
       - organization (Organization)

     Example curl:
       curl -s -X POST "http://localhost:8002/raystack.frontier.v1beta1.FrontierService/CreateOrganization" \
         -H "connect-protocol-version: 1" \
         -H "content-type: application/json" \
         -H "Cookie: sid=<TOKEN>" \
         -d '{"body":{"name":"my-org","title":"My Org"}}'
   ```

5. Always generate a ready-to-use curl example with sensible placeholder values based on the field types.

---

## GitOps: reconcile

Frontier manages platform-level resources from a file instead of one-off API calls. You write down what should exist, `frontier reconcile` compares the file with the running server, prints a plan, and applies the difference through the admin API. This is the flow described in [RFC 0001](https://github.com/raystack/frontier/blob/main/docs/rfcs/0001-declarative-reconcile.md).

It runs against the **local running server** — the same one from [Step 8](#step-8-start-frontier-in-background). It is a client, so the server does not need a restart.

### The five kinds

| Kind | Spec fields | Identity | Entry left out of the file | How to remove |
|---|---|---|---|---|
| `PlatformUser` | `type`, `ref`, `relation` | principal + relation | access is removed | leave the entry out |
| `Permission` | `namespace`, `name`, `delete` | namespace + name | **plan fails** | `delete: true` |
| `Role` (custom) | `name`, `title`, `description`, `permissions`, `scopes`, `delete` | name | **plan fails** | `delete: true` |
| `Role` (predefined) | same | name | resets to the shipped definition | cannot be removed |
| `Preference` | `name`, `value` | trait name | resets to the trait default | leave the entry out |
| `Webhook` | `url`, `description`, `subscribed_events`, `state`, `delete` | URL | **plan fails** | `delete: true` |

Two behaviours to explain to the user when a plan surprises them:

- **Objects** (Permission, Webhook, custom Role) are things reconcile creates and deletes. Every one on the server must appear in the file. One that is missing **fails the plan** — it is not silently deleted, and it is not silently ignored.
- **Values** (PlatformUser, Preference, predefined Role) always exist and have a default. Leaving one out resets it to the default. For `PlatformUser` that means **the file is the full access list** — an admin you forget to list loses admin.

One field rule everywhere: a field you write is the whole value, a field you leave out takes the default, an empty field (`""` or `[]`) means empty. Nothing merges.

### File format

One or more YAML documents, separated by `---`. Each has a `kind` and a `spec`:

```yaml
apiVersion: v1
kind: PlatformUser
spec:
  - type: user
    ref: alice@raystack.org
    relation: admin
---
apiVersion: v1
kind: Permission
spec:
  - namespace: compute/order
    name: get
```

- `apiVersion` may be left out — it reads as `v1`. Any other value is rejected.
- A document with content but no `kind`, or with no `spec`, is rejected. To mean an empty list, write `spec: []` on purpose.
- In one file, a kind must come after the kinds it depends on. `Role` references `Permission`, so `Permission` documents go first.
- The whole file is checked before anything is applied.

### Getting the file path

Do NOT guess or scan for the file. Ask once, then remember it.

**On every reconcile, read `.config.json` first.** Two shapes are supported. Check for both:

- **`reconcile_file`** — a single path. The simple case: one file, possibly holding several documents.
- **`reconcile`** — a block, for the layout where each kind lives in its own file. Shape:

  ```json
  {
    "reconcile": {
      "config_dir": "/abs/path/to/config/dir",
      "files": {
        "Permission":   "/abs/.../permissions.yaml",
        "Role":         "/abs/.../roles.yaml",
        "PlatformUser": "/abs/.../platform_users.yaml",
        "Preference":   "/abs/.../preferences.yaml"
      },
      "apply_order": ["Permission", "Role", "PlatformUser", "Preference"],
      "needs_render": ["Preference"],
      "host": "http://localhost:8002",
      "bootstrap_creds_from": "/abs/path/to/frontier/config.yaml -> app.admin.bootstrap"
    }
  }
  ```

Then:

- **A stored entry exists and the files are there** → use it. Say which, in one line: `Using desired-state files from <config_dir>`.
- **A stored entry exists but a file is gone** → say which one, and ask again. Do not silently fall back to another file, and do not go hunting for a moved copy.
- **Nothing stored** → ask with a plain text prompt (free-form, so no `AskUserQuestion`):

  > Where are your desired-state files? Give me an absolute path — a single YAML file, or a directory holding one file per kind. (Or say "sample" to copy the plugin's `sample.platform-users.yaml` into `~/frontier-test/platform-users.yaml`.)

**If the answer is a directory**, list it and work out the layout yourself:

```bash
ls -1 <dir>
```

Match files to kinds by name: `*platform_users*` / `*platformuser*` → `PlatformUser`, `*permission*` → `Permission`, `*role*` → `Role`, `*preference*` → `Preference`, `*webhook*` → `Webhook`. Confirm each guess by reading the `kind:` line inside the file — the filename is a hint, the `kind:` field is the answer. Build the `reconcile` block from what you find, write it to `.config.json`, and `chmod 600` the file.

If a directory holds several files that map to the same kind, do not guess. List them and ask which one to use.

**Then ask which kinds to run.** Use `AskUserQuestion` with `multiSelect: true`, one option per kind found. Do not assume "all" — a `PlatformUser` file is authoritative and deserves its own decision.

**Save whatever the user picked** and reuse it in this and future sessions. Only re-ask when the user says **reconcile file** / **change reconcile file**, or a saved path has gone missing.

If the user names a file inline (`reconcile ~/other.yaml`), use it for this run and ask whether to make it the default:

```
question: "Save <path> as the default reconcile file?"
header:   "Default file"
multiSelect: false
options:
  - label: "Yes — make it the default (Recommended)"
    description: "Write it to .config.json. Future 'reconcile' commands use this file without asking."
  - label: "No — just this once"
    description: "Use it for this run only. Keep the saved default as it is."
```

### Rendering templated files

A file with a `.ctmpl` extension, or one containing `{{`, is a [consul-template](https://github.com/hashicorp/consul-template) source, not finished YAML. Check before running:

```bash
grep -c '{{' <file>
```

If the count is zero, use the file as-is. If not, do NOT feed it to `reconcile` — the raw template text would be treated as the desired value and would plan a bogus change. Two cases:

1. **Escaped braces only** — the file is plain YAML that carries `{{...}}` placeholders through to the server (Frontier's invite-mail body does this). They appear as `{{ "{{" }}.UserID{{ "}}" }}`. Render them with a copy, never in place:
   ```bash
   sed -e 's/{{ "{{" }}/{{/g' -e 's/{{ "}}" }}/}}/g' <file> > <scratchpad>/<kind>.yaml
   ```
2. **Real template directives** — anything with `{{ with secret ... }}`, `{{ .Data... }}`, or an `{{ if }}`. These need secrets this skill does not have. Stop and tell the user the file must be rendered by their own tooling first, and ask for the rendered path. Do not guess at values.

Always render into the scratchpad, never over the user's file. After rendering, confirm no markers are left (`grep -c '{{ "'` returns 0) and that the YAML parses, then reconcile the rendered copy. Record which kinds needed rendering under `needs_render` in `.config.json` so later runs know to do it again.

### Running several files in one go

When the layout is one file per kind, run one `reconcile` per file rather than concatenating them. Order matters: **Permission → Role → PlatformUser → Preference**. `Role` entries reference permissions by name, so permissions must exist first.

Dry-run every selected kind before applying any of them. Show all the plans together, then ask once. Applying kind by kind while plans for later kinds are still unknown hides the full blast radius.

### Building the command

The CLI is the Frontier binary already built in [Step 6](#step-6-clone-and-build-frontier): `~/frontier-test/frontier`.

```bash
BASIC=$(printf '%s:%s' "<bootstrap_client_id>" "<bootstrap_client_secret>" | base64)

~/frontier-test/frontier reconcile \
  -f "<reconcile_file>" \
  --host "http://<SERVER>" \
  -H "Authorization:Basic ${BASIC}" \
  --dry-run
```

Flag details that bite:

- **`--host` needs the scheme.** Without `http://` the CLI prepends `https://` and the call fails against a local server. Always pass `http://localhost:8002` (or whatever `server` is in `.config.json`), never a bare `localhost:8002`.
- **`-H` takes one `key:value` string**, split at the first colon. So the value is `Authorization:Basic <base64>` — one argument, no space after the colon.
- **`-f` is required.** `--dry-run` is the only thing standing between a plan and a real change.
- Auth can also be a session cookie — `-H "Cookie:sid=<token>"` for a reconciled platform admin. Basic auth with the bootstrap account is the safer default because it never expires and works on a fresh server. Fall back to the cookie only if the bootstrap pair is missing from `.config.json`.
- Never let the base64 credential appear in output. When you show the user the command, print it with `-H "Authorization:Basic ***"`.

**If the bootstrap pair is not in `.config.json`,** read it back out of the server's own `config.yaml` instead of asking the user to paste a secret. Keep it in shell variables so it never reaches the transcript:

```bash
CFG=~/frontier-test/config.yaml   # or the config the running server was started with
CID=$(awk '/^ *bootstrap:/{f=1} f&&/client_id:/{gsub(/.*client_id: *"?|"$/,"");print;exit}' "$CFG")
CSEC=$(awk '/^ *bootstrap:/{f=1} f&&/client_secret:/{gsub(/.*client_secret: *"?|"$/,"");print;exit}' "$CFG")
BASIC=$(printf '%s:%s' "$CID" "$CSEC" | base64 | tr -d '\n')
```

`tr -d '\n'` matters — some `base64` builds wrap long lines, and a newline inside a header value breaks the request. Print at most `client_id: $CID   secret: *** (len ${#CSEC})` so the user can see it was found without the secret leaking. Then offer to save the pair to `.config.json` so the next run skips this step.

### The reconcile flow

Always dry run first. Every time — even when the user types **apply**.

**1. Dry run.** Run the command above with `--dry-run`.

**2. Show the plan verbatim.** The output is one block per kind:

```
PlatformUser (planned 2):
  - add user alice@raystack.org as admin
  - remove user bob@raystack.org (admin)
Permission: no changes
```

Print it exactly as the CLI produced it. Do not summarise it away, and do not reorder it. Then add a short plain-English read underneath, and call out anything risky:

- Any `remove` / `delete` line — name who or what loses access.
- A `PlatformUser` plan that removes the user's own account, or removes the last admin.
- A plan that fails (for example, a permission on the server that is not in the file) — show the error and stop. There is nothing to apply.

**3. Ask before applying.** Use `AskUserQuestion`:

```
question: "Apply this plan to <SERVER>? (<N> changes, <M> removals)"
header:   "Apply plan"
multiSelect: false
options:
  - label: "Cancel (Recommended)"
    description: "Don't touch the server. The dry run already showed you the diff — re-run once you've edited the file."
  - label: "Apply"
    description: "Run the same command without --dry-run. Adds and updates go first, then deletes. There is no rollback."
```

Put "Cancel" first. Two exceptions to the recommended label: if the plan has zero changes, say so and skip the question entirely. If the plan has no removals and the user explicitly typed **apply**, you may mark "Apply" as recommended instead.

If `<SERVER>` is not localhost, this is also a [Remote Host Protection](#remote-host-protection) case — use that stricter wording.

**4. Apply.** Re-run the exact same command with `--dry-run` dropped. Nothing else changes.

**5. Report.** Show the output, which now reads `applied N` instead of `planned N`. Then say in one line what changed.

**Read `applied N`, not the list.** On a failed run the CLI still prints the whole plan, then the error at the bottom. The list is what it *intended* to do, not what it did. `PlatformUser (applied 0)` followed by 51 lines means **nothing happened** — do not report those 51 lines as changes. Always quote the `applied N` count, and when N is 0 say plainly that the server is unchanged.

If a call fails partway: there is no rollback, and the loop stops at the first error (`platformuser_reconciler.go`, the apply loop). Adds and updates run before deletes, so a half-finished run has left *more* access, not less — a failing add means no removal ever ran. Tell the user the error, and that the fix is always the same: fix the cause and reconcile again. Whatever already applied will plan no change the second time.

**Then verify, don't assume.** After any apply, re-read the live state and compare it against what you claimed. For `PlatformUser` that is one call:

```bash
curl -s -X POST "http://<SERVER>/raystack.frontier.v1beta1.AdminService/ListPlatformUsers" \
  -H "connect-protocol-version: 1" -H "content-type: application/json" \
  -H "Authorization: Basic ${BASIC}" -d '{}'
```

Counts before and after are enough. This is the only way to tell a real apply from a plan that printed and died.

**Resolve ids to names in any plan you show.** The plan prints removals by uuid (`remove user d4aca6d7-…`), which tells the user nothing about who loses access. Before asking to apply, call `ListPlatformUsers`, build an id→email map, and list the affected people by email. Also say who is **kept** — especially whether the user's own account survives. A plan that silently drops the operator's own admin is the worst outcome here, and the uuid list hides it.

### Export: seed a file from the server

`frontier export <kind>` prints the live state in the same format. Reconciling an export plans zero changes, so it is the safe way to write a file for the first time.

```bash
~/frontier-test/frontier export platformuser \
  --host "http://<SERVER>" \
  -H "Authorization:Basic ${BASIC}"
```

- The kind argument is case-insensitive and takes a trailing `s`: `platformuser`, `PlatformUser`, and `platformusers` all work.
- Output goes to stdout. To write a file, redirect: `> ~/frontier-test/platform-users.yaml`.
- Before redirecting over a file that already exists, back it up: `cp <file> <file>.bak.$(date +%s)`, and tell the user.
- Use this when the user has no desired-state file yet, or when a plan shows drift they did not expect and they want to start from what is actually there.

### Adding a Superadmin

When the user says **add superadmin &lt;email&gt;** or **make me superadmin**:

1. Get the reconcile file (see [Getting the file path](#getting-the-file-path)). If there is none, export the current state into `~/frontier-test/platform-users.yaml` first, so the file starts as the truth and the new entry is the only change.
2. Read the file. If a `PlatformUser` document already has that `ref` with `relation: admin`, say so and stop — nothing to do.
3. Back up the file (`cp <file> <file>.bak.$(date +%s)`), then append the entry to the existing `PlatformUser` spec. Do not create a second `PlatformUser` document — one kind, one document.
   ```yaml
     - type: user
       ref: <email>
       relation: admin
   ```
4. Show the user the diff — just the added lines.
5. Run the normal [reconcile flow](#the-reconcile-flow): dry run, show plan, ask, apply.
6. After applying, the user still needs a fresh session. Drop any stored cookie for that email from `.cookies.json` and re-run [Automatic Login](#automatic-login-mailotp-flow) so the new grant is picked up.

An email that does not exist in Frontier is **created** by the reconcile run. That is expected, not an error.

### Safety rules for reconcile

These sit on top of the general [Safety Rules](#safety-rules).

- **Never apply without a dry run first**, and never without showing the plan. The CLI itself does not ask for confirmation — this skill is the only guard.
- **Never edit the user's desired-state file without saying so.** Back it up, change the minimum, show the diff.
- **Treat a `PlatformUser` file as the full access list.** Before applying a plan that removes admins, spell out exactly who loses access. Editing a file by hand and forgetting an existing admin is the easiest mistake to make here.
- **Refuse to apply against a non-localhost server** without the explicit [Remote Host Protection](#remote-host-protection) confirmation. A reconcile can strip every admin from a shared environment in one call.
- **`localhost` is not proof the target is local.** A port-forward or tunnel puts a shared server on a local port. Before an apply, confirm the port is the one Frontier was started on in [Step 8](#step-8-start-frontier-in-background) — the `server` value in `.config.json`, normally `8002`. If the port is anything else, treat it as remote and use [Remote Host Protection](#remote-host-protection), whatever the hostname says.
- **The file and the `--host` are two separate decisions.** Only the host decides what gets written. Reading a shared server's desired-state file into your local sandbox is the normal way to test a change before it ships; pointing the command at that shared server is not. Say which server the plan targets every time you show a plan, so the direction is never in doubt.
- **Never print the bootstrap client secret or the base64 Basic value.** Mask them everywhere, including in the command you echo back.
- **Do not invent kinds or fields.** If the user asks for something outside the five kinds, say it is not managed by reconcile and point them at the ordinary RPCs. Reconcile does not manage organizations, projects, groups, users, or policies by design.

---

## UI Testing

Drive the two Frontier web apps through a real browser so UI engineers can exercise full user flows (button clicks, form fills, navigation, table assertions) without leaving the skill. Both apps live in the frontier monorepo, share a JS SDK, and talk to the same ConnectRPC backend the [RPC flow](#services) already targets.

| App | Folder | Purpose | Who can sign in | `.env` keys |
|-----|--------|---------|-----------------|-------------|
| **client-demo** | `web/apps/client-demo` | End-user-facing demo app (sign-in, orgs, projects, settings) | Any logged-in user | `FRONTIER_CONNECT_ENDPOINT` |
| **admin** | `web/apps/admin` | Platform admin UI | Platform admins only — users granted `relation: admin` via [reconcile](#gitops-reconcile) | `FRONTIER_API_URL` (port 8000 HTTP API) + `FRONTIER_CONNECTRPC_URL` (port 8002) |

> Note: the admin app folder is **`admin`**, not `admin-app`. The package name in `package.json` is `admin`. Don't try to write to `apps/admin-app/` — it doesn't exist.

Both apps consume the **Frontier JS SDK** (`web/sdk`, package `@raystack/frontier`, built via `tsup`). Any SDK source change requires `pnpm run build` in the SDK package before the apps pick it up; app source changes are picked up by Vite HMR automatically.

The two apps don't share the same backend ports: client-demo talks to ConnectRPC on `:8002` only, while admin needs **both** `:8000` (gRPC-gateway HTTP API) and `:8002` (ConnectRPC). If your local Frontier setup only runs ConnectRPC, the admin app will partially work — sign-in via mailotp works (it goes through `:8002`) but pages that depend on the HTTP API will fail to load. Surface this clearly before launching admin if `:8000` is not listening.

### Selecting an App

When the user types just `ui` / `open ui` (no app name), ask via `AskUserQuestion`:

```
question: "Which app would you like to launch?"
header:   "App"
multiSelect: false
options:
  - label: "client-demo (Recommended)"
    description: "End-user demo app on `web/apps/client-demo`. Talks to Frontier ConnectRPC on :8002 only. Sign in as any raystack.org user."
  - label: "admin"
    description: "Platform admin UI on `web/apps/admin`. Needs Frontier HTTP gateway on :8000 AND ConnectRPC on :8002. Super-admin sign-in only (+sa users)."
  - label: "Both"
    description: "Launch both dev servers in parallel and open both tabs."
  - label: "Cancel"
    description: "Just show current ui status — don't launch anything."
```

If the user uses the explicit `client-demo` / `admin` / `open <name>` shorthands, skip this question and go straight to launching that one.

### UI Prerequisites

Before any UI command, verify these. If anything is missing, **stop and tell the user** — do NOT install Node/pnpm/MCPs silently.

1. **pnpm** — `pnpm --version`. If missing, suggest `corepack enable && corepack prepare pnpm@latest --activate`.
2. **Node.js >= 20** — `node --version`. If too old, ask the user how they manage Node (nvm/fnm/asdf) and let them upgrade.
3. **chrome-devtools-mcp tools** — confirm that browser-driving tools (e.g. `mcp__chrome-devtools__*` or equivalent) are listed as available in the current conversation. If they aren't, tell the user:
   > UI testing needs the chrome-devtools-mcp plugin. Install it (e.g. via `/plugin install chrome-devtools-mcp`) and restart Claude Code, then re-run the UI command.
   Do not try to script the browser by other means.
4. **Frontier source cloned** — `~/raystack/frontier` must exist. If not, route the user through [Step 6: Clone and Build Frontier](#step-6-clone-and-build-frontier) first (only the clone step is needed — the Go build is optional for UI-only work).

### Path Discovery (first UI run)

On the first UI command (or if `.config.json` has no `ui` block), discover the web monorepo layout inside `~/raystack/frontier`. Don't hardcode — the layout has changed across Frontier versions.

```bash
FRONTIER=~/raystack/frontier

# Find the web/JS workspace root (must contain a pnpm-workspace.yaml)
for candidate in "$FRONTIER/web" "$FRONTIER/sdks/js" "$FRONTIER"; do
  if [ -f "$candidate/pnpm-workspace.yaml" ]; then
    echo "WEB_ROOT=$candidate"; break
  fi
done
```

If none of the candidates have `pnpm-workspace.yaml`, ask the user for the absolute path to the web workspace.

From `WEB_ROOT`, locate the two apps and the SDK. Read `pnpm-workspace.yaml` for the glob patterns, then resolve concrete paths:

```bash
# Apps — usually web/apps/client-demo and web/apps/admin, but names can drift
ls -d "$WEB_ROOT"/apps/*/  2>/dev/null
# SDK — try common locations
ls -d "$WEB_ROOT"/sdk        2>/dev/null
ls -d "$WEB_ROOT"/packages/* 2>/dev/null
```

Match folders by their `package.json` `name` field when names are ambiguous. The current Frontier layout has `apps/admin` (not `admin-app`) — never assume the dashed form. If both expected apps are not present under `apps/`, ask via `AskUserQuestion` with the detected folder list as options:

```
question: "Which folder is the <client-demo|admin> app?"
header:   "App folder"
multiSelect: false
options:
  - label: "<detected_folder_1>"
    description: "package.json name: <name>, dev script: <pnpm script>"
  - label: "<detected_folder_2>"
    description: "package.json name: <name>, dev script: <pnpm script>"
  - label: "Not present — skip this app"
    description: "Don't launch this app. We'll only set up the other one."
```

(Pick at most 3 folders to surface. If there are more, summarise and fall back to a free-text prompt for the path.)

Pick the right endpoint env keys per app by reading the existing `.env`/`.env.example`:

```bash
grep -E '^(VITE_)?FRONTIER_[A-Z_]+_(URL|ENDPOINT)=' <app_path>/.env <app_path>/.env.example 2>/dev/null
```

- client-demo: typically a single `FRONTIER_CONNECT_ENDPOINT` (ConnectRPC).
- admin: typically **two** keys — `FRONTIER_API_URL` (gRPC-gateway HTTP API, port 8000) and `FRONTIER_CONNECTRPC_URL` (ConnectRPC, port 8002). When the user says `point admin to <url>`, only rewrite `FRONTIER_CONNECTRPC_URL` by default (the HTTP gateway is usually a different deployment target). Confirm if unsure.

Save under a new `ui` block in `.config.json`:
```json
{
  "ui": {
    "web_root": "/Users/<you>/raystack/frontier/web",
    "sdk_path": "/Users/<you>/raystack/frontier/web/sdk",
    "sdk_package_name": "@raystack/frontier",
    "sdk_build_script": "build",
    "sdk_source_git_hash": null,
    "apps": {
      "client-demo": {
        "path": "/Users/<you>/raystack/frontier/web/apps/client-demo",
        "endpoint_env_keys": ["FRONTIER_CONNECT_ENDPOINT"],
        "repoint_keys": ["FRONTIER_CONNECT_ENDPOINT"],
        "pid": null,
        "actual_port": null
      },
      "admin": {
        "path": "/Users/<you>/raystack/frontier/web/apps/admin",
        "endpoint_env_keys": ["FRONTIER_API_URL", "FRONTIER_CONNECTRPC_URL"],
        "repoint_keys": ["FRONTIER_CONNECTRPC_URL"],
        "pid": null,
        "actual_port": null
      }
    }
  }
}
```

`endpoint_env_keys` is the full set the skill should display in `ui status`. `repoint_keys` is the subset that the `point <app> to <url>` command rewrites — by design narrower so the rewrite doesn't clobber unrelated endpoints. Apply `chmod 600 ~/frontier-test/.config.json` after writing (per [File Permissions](#file-permissions)).

### Reading and Writing App `.env`

Each app has a `.env` (or `.env.local`) in its directory. The key the skill cares about is `FRONTIER_CONNECT_ENDPOINT` — it tells the app which Frontier backend to call.

**Reading** — show only this key, never the full file:
```bash
grep -E '^(FRONTIER_CONNECT_ENDPOINT|VITE_FRONTIER_CONNECT_ENDPOINT)=' <app_path>/.env 2>/dev/null
```
(Vite-style apps usually use a `VITE_` prefix. Check the app's `vite.config.*` or existing `.env.example` for the actual key name and store it under `ui.apps.<name>.endpoint_env_key`.)

**Default** — when the user hasn't customised: `FRONTIER_CONNECT_ENDPOINT='http://localhost:8002'` (matches the local Frontier from [Step 8](#step-8-start-frontier-in-background)).

**Writing** — when the user says `point client-demo to <url>` (or `point admin to <url>`):

Use the `repoint_keys` stored in `.config.json` for that app — never blanket-rewrite every `FRONTIER_*_URL` line. For admin, that defaults to **only** `FRONTIER_CONNECTRPC_URL`. If the user says "repoint both" or names a specific key, honour that.


1. If `<url>` is not `localhost` / `127.0.0.1`, ask via `AskUserQuestion` (this is a specialisation of [Remote Host Protection](#remote-host-protection)):

   ```
   question: "Repoint <app> from <current_url> to <new_url>?"
   header:   "Remote endpoint"
   multiSelect: false
   options:
     - label: "Cancel (Recommended)"
       description: "Don't rewrite the .env. <new_url> is not localhost — a UI action could mutate prod data."
     - label: "Proceed — repoint <repoint_keys>"
       description: "Rewrite the configured keys (<repoint_keys>) only, back up the .env, restart the app."
     - label: "Proceed and rewrite ALL FRONTIER_*_URL keys"
       description: "Override the narrower repoint_keys list and rewrite every Frontier endpoint key in the .env. Only do this if you really mean both API and ConnectRPC live at <new_url>."
   ```

   Even a read-only-looking UI can trigger writes via the SDK.
2. If `.env` exists, back it up: `cp <app_path>/.env <app_path>/.env.bak.$(date +%s)`. If only `.env.example` exists, copy it to `.env` first.
3. Read `.env` line-by-line. Replace the existing `FRONTIER_CONNECT_ENDPOINT=` (or `VITE_FRONTIER_CONNECT_ENDPOINT=`) line, preserving all other entries. If the key is absent, append it.
4. `chmod 600 <app_path>/.env`.
5. If the app is currently running (PID alive), restart it (kill + relaunch) so the new endpoint is picked up — Vite reads `.env` at startup, not on change.

Never echo `.env` contents in full — they may contain other secrets (analytics keys, client IDs, etc.). Show only the line you changed, masking values that look secret.

### Build the SDK

The SDK must be built before either app is launched for the first time. Build cache: skip if the SDK source git hash hasn't changed AND a build output directory exists.

```bash
SDK_HASH=$(cd <sdk_path> && git rev-parse HEAD)
# Compare with `ui.sdk_source_git_hash` in .config.json
# Also check that <sdk_path>/dist (or whatever "main"/"exports" points at in package.json) exists
```

If a rebuild is needed:

```bash
cd <sdk_path>
[ -f pnpm-lock.yaml ] && pnpm install --frozen-lockfile || pnpm install
pnpm run build
```

After a successful build, update `ui.sdk_source_git_hash` in `.config.json` to the new `SDK_HASH`.

If `pnpm run build` exits non-zero: show the last 30 lines of stderr, tell the user the SDK didn't build, **stop** — do not start any app on a broken SDK.

If the SDK package doesn't define a `build` script, look at `package.json` for the actual script name (`build:lib`, `prepublishOnly`, etc.) and use that; save the resolved name under `ui.sdk_build_script` for next time.

### Start an App in the Background

For client-demo or admin:

```bash
APP_DIR=<app_path>
cd "$APP_DIR"
[ -f pnpm-lock.yaml ] && pnpm install --frozen-lockfile || pnpm install
pnpm run dev > "$APP_DIR/.dev.log" 2>&1 &
echo $! > "$APP_DIR/.dev.pid"
chmod 600 "$APP_DIR/.dev.log" "$APP_DIR/.dev.pid"
```

Save the PID under `ui.apps.<name>.pid` in `.config.json`.

**Detect the bound port.** Vite versions and per-app `vite.config.*` settings vary — observed defaults in this codebase include `:3000` for client-demo, but it can change. Never hardcode a port. Tail the log until a URL appears (apply [Health Check Timeout](#health-check-timeout) — 30s cap):

```bash
# Poll the log up to 30s
for i in $(seq 1 30); do
  URL=$(grep -Eo 'http://localhost:[0-9]+' "$APP_DIR/.dev.log" | head -1)
  [ -n "$URL" ] && break
  sleep 1
done
```

Store the URL/port under `ui.apps.<name>.actual_port`. If no URL appears in 30s, show `tail -50 .dev.log` and ask the user whether to retry, debug, or stop.

**Port conflict** with the backend Frontier port (`8002` from Step 8): if Vite somehow grabs that port, refuse and ask the user — never let an app collide with Frontier.

### Open in Browser via chrome-devtools-mcp

Once the URL is known, drive the browser with the chrome-devtools-mcp tools available in the session. The exact tool names depend on the installed MCP — discover them at use time, don't hardcode here. Typical capabilities to use:

| Intent | Use |
|--------|-----|
| Open the app | A "navigate" / "new page" tool with the URL from `actual_port` |
| Find/click a button | A "snapshot" or "query" tool to locate the element by visible text / role / `data-testid`, then a "click" tool |
| Fill a form | A "type" / "fill" tool keyed by label or `data-testid` |
| Read state | A "snapshot" / "get text" tool to verify what's on screen |
| Capture failure | A "screenshot" tool, saved to `~/frontier-test/ui-screenshots/<timestamp>.png` (`mkdir -p` first, `chmod 600`) |

Selector strategy, in priority order:
1. Visible label / role / accessible name (most stable across refactors)
2. `data-testid` if present
3. CSS selector or `nth-of-type` only as a last resort, and warn the user that the selector is fragile

After each meaningful action, take a follow-up snapshot and tell the user **what changed** in one sentence, not a dump of the DOM.

### Driving the Login Flow

Both apps use the mailotp flow that the [Automatic Login](#automatic-login-mailotp-flow) section already documents. In the UI:

1. Use the configured `test_otp` and `test_domain` (`raystack.org`) from `.config.json` — same source of truth as the RPC flow.
2. For **admin**, the email must be a reconciled platform admin. If the user doesn't specify one, read `reconcile_file` from `.config.json` and use the first `PlatformUser` entry with `relation: admin`; fall back to `admin1+sa@raystack.org`. If that email isn't in the reconcile file, the sign-in will succeed but the admin pages will 403 — say so up front and offer [Adding a Superadmin](#adding-a-superadmin).
3. For **client-demo**, any `raystack.org` email works; default to `user1@raystack.org` if unspecified.
4. Drive the form, watching for these concrete button/page labels in the current Frontier UI:
   - The button reads **"Continue with Email"** (not "Send OTP"). Clicking it reveals an email textbox + a now-enabled "Continue with Email" button.
   - After submitting the email, the page redirects to **`/magiclink-verify?state=<uuid>&email=<urlencoded>`** with heading "Check your email" and an "Enter OTP" textbox. Despite the route name including "magiclink", entering the configured `test_otp` and clicking "Submit OTP" completes the flow.
   - On success, the user lands on `/` (client-demo) with the user initial visible in the top-right menu button.
5. Re-check the DOM after each step — don't blast all clicks before the next view renders.
6. If login fails (wrong email domain, backend down, OTP rejected), surface the on-screen error message verbatim. Don't retry silently more than once.

The skill must NOT bypass the UI to forge a cookie — the point of UI testing is exercising the real flow. If the user explicitly says "skip the login UI", do the [Automatic Login](#automatic-login-mailotp-flow) curl flow, drop the `sid` cookie into the browser via a chrome-devtools-mcp cookie tool, and reload.

### Rebuild Loop (SDK changes)

When the user says `sdk rebuild`, `rebuild sdk`, or "I changed the SDK":

1. Run [Build the SDK](#build-the-sdk) (respecting the build cache).
2. If the build fails, **stop** — leave running apps alone. The user can fix and retry.
3. If the build succeeds, for each app whose PID is alive:
   - Try a soft refresh first: use the chrome-devtools-mcp reload/navigate tool on the open tab. With Vite + workspace deps, HMR usually picks up the new SDK without a dev-server restart.
   - If the page console shows the old SDK is still loaded (e.g. the user reports stale behaviour), then hard-restart the dev server: graceful-kill the PID, relaunch via [Start an App in the Background](#start-an-app-in-the-background), refresh the browser tab.
4. Tell the user which path was taken (soft reload vs full restart).

For pure app source changes (no SDK touched), HMR handles it — no action needed unless the user reports HMR is broken.

### UI Status

When the user says `ui status`:

For each entry in `ui.apps`:
- **Running?** Apply [Stale PID Detection](#stale-pid-detection) on the stored PID (process name should contain `node` or `pnpm` or the app slug). Clear the PID if stale.
- **Port** — from `actual_port`. Verify with `lsof -i :<port> -sTCP:LISTEN`.
- **Endpoint** — read `FRONTIER_CONNECT_ENDPOINT` (or `VITE_…`) from the app's `.env`. Show only the value, no other env lines.

For the SDK:
- Show `sdk_source_git_hash` (short form) and whether the build output exists.
- If the current `git rev-parse HEAD` in the SDK differs from the stored hash, flag it: `SDK source has changed since last build — run "sdk rebuild" to pick it up.`

Format the output as a compact table, e.g.:
```
App           PID    Port   Endpoint                                 Browser
client-demo   12345  3000   FRONTIER_CONNECT_ENDPOINT=…:8002         open
admin         —      —      FRONTIER_API_URL=…:8000, …RPC_URL=…:8002 —

SDK build:    commit a1b2c3d (matches HEAD)
```

For the admin app, show both endpoint env values (one per line if it doesn't fit on one row). If the configured `FRONTIER_API_URL` host is not reachable, append a small warning: `(WARN: API URL host not reachable — UI will partially fail)`.

### UI Teardown

When the user says `ui stop` / `stop ui`, or as part of full `teardown`:

1. For each app with a stored PID, apply [Graceful Shutdown](#graceful-shutdown) and [Stale PID Detection](#stale-pid-detection). Kill the dev server, wait for the port to free.
2. Clear `pid` and `actual_port` in `.config.json`; keep `path` and `endpoint_env_key`.
3. Leave the SDK build output on disk — it's just files.
4. Do NOT touch the backend (Frontier, SpiceDB, Postgres). UI teardown is independent of backend teardown unless the user explicitly asks for "teardown everything".

When the user says **just `teardown`** (no scope) and BOTH the UI and backend are running, disambiguate with `AskUserQuestion`:

```
question: "What should be stopped?"
header:   "Teardown scope"
multiSelect: false
options:
  - label: "UI only (Recommended)"
    description: "Stop client-demo + admin dev servers. Leave Frontier / SpiceDB / Postgres running so you can keep hitting the backend via curl."
  - label: "Backend only"
    description: "Stop Frontier (and SpiceDB / Postgres / containers depending on setup_mode). Keep the UI dev servers running — they'll show errors until backend is back."
  - label: "Everything"
    description: "Stop UI dev servers AND backend. After this, a future `/frontier-sandbox` invocation will run the full startup flow again."
  - label: "Cancel"
    description: "Don't stop anything."
```

If the user explicitly says `ui stop` / `stop ui` skip this question and only stop the UI. If they explicitly say `stop` / `teardown` and only one layer is running, also skip the question and just stop that layer.

### Role-Name Mapping

Frontier's UI exposes these org-level roles (verified in client-demo invite flow):

| Role in UI | What the user usually means |
|---|---|
| **Organization Owner** | "owner", "founder" |
| **Organization Manager** | "admin", "org admin", "full admin access" |
| **Organization Access Manager** | "access admin", "permissions manager" |
| **Organization Viewer** | "read-only", "viewer" |
| **Billing Manager** | "billing admin" |

There is **no role literally called "Admin"**. When the user says "invite X as org admin", confirm the mapping with `AskUserQuestion` instead of guessing:

```
question: "Frontier has no 'Admin' role. Which one do you mean for <email>?"
header:   "Role"
multiSelect: false
options:
  - label: "Organization Manager (Recommended)"
    description: "Closest to admin — full org management. Can invite/remove members, manage projects, settings."
  - label: "Organization Owner"
    description: "Highest privilege — full control including org deletion. Usually only the founder."
  - label: "Organization Access Manager"
    description: "Can manage member roles and permissions but not org settings."
  - label: "Organization Viewer"
    description: "Read-only across the org."
```

(Billing Manager exists but is a separate scope — not interchangeable with "admin". Don't include it in this picker unless the user explicitly mentions billing.)

Newly-invited members appear in the table as **"Member (Pending invite)"** until they accept — the chosen role only applies post-acceptance. Use this row text in `wait_for` after sending an invite.

### chrome-devtools-mcp — Tool Quirks That Trip the Skill

These are real behaviours observed driving client-demo. Follow them or the skill leaks secrets, clicks the wrong thing, or stares at empty snapshots.

1. **uids reset on every navigation.** `take_snapshot` returns a fresh id space after each page load. NEVER reuse a uid from a previous snapshot after `navigate_page`, after a route-changing click, or after a server redirect (e.g. login → `/`). Always re-snapshot first.

2. **Default snapshots hide tabular data.** For tabular settings pages (Projects, Members, Service Accounts, Personal Access Tokens), the row containers are wrapped in non-semantic divs that the a11y tree marks as `ignored`. The plain snapshot returns only headings + column labels. **Use `take_snapshot({verbose: true})` for any tabular view.** Even with `verbose: true`, per-row inline action menus are sometimes unreachable from the a11y tree — for destructive actions, drill into the detail page (e.g. click the row name) and use the page-header action menu there.

3. **`wait_for` always returns the full DOM snapshot. There is no opt-out.** This means if you `wait_for` text on a page that displays a freshly-issued secret (Initial Generated Key for a service account, PAT value), that secret lands in your conversation context. There is no flag to suppress it.

4. **Credential-creation safe pattern.** For service accounts, PATs, and any flow that lands on a page showing a one-time secret immediately after submission:

   ```
   click(submit_button_uid)                                  # do NOT pass includeSnapshot
   navigate_page("http://…/<parent-list-url>")               # navigate AWAY before reading
   wait_for(["<toast or row-text from list page>"])          # now safe — the secret-bearing page is gone
   ```

   Empirical: in client-demo, the "Initial Generated Key" Basic auth token is **one-time display** — it disappears from the DOM once you navigate away from the detail page. So the navigate-then-wait pattern genuinely removes the leak from any subsequent snapshot.

   Conversely: `click({includeSnapshot: true})` after submitting and `wait_for` on the detail page DO leak the key into the conversation. If you find yourself thinking "I just need to confirm it worked," prefer toast text from the list page over snapshotting the detail page.

5. **Multi-select dropdowns: click the inner checkbox, not the option.** In Frontier's project picker (and elsewhere), clicking the `option` element moves focus but does NOT toggle the checkbox state. Click the nested `checkbox` element directly (uid one level deeper than the option). Verify the combobox's `value=` attribute updated before continuing.

6. **Close open dropdowns before clicking dialog primary actions.** When a select menu is open inside a modal dialog, clicking the dialog's "Create"/"Save" button at the bottom can register on a focused option in the overlay menu instead of the button below, silently toggling the option off and not submitting the form. Always click the combobox to collapse it first, then click the primary action.

7. **For destructive actions on tabular settings pages, drill into the detail page.** Service Accounts, PATs etc. expose per-row action menus that aren't in the a11y snapshot. Click the row name → wait for "<entity> actions" (or similar) button in the breadcrumb header → open menu → choose "Delete". Confirm dialog (`alertdialog` role) → click "Delete".

### Safety Recap for UI

The general [Safety Rules](#safety-rules) all apply. Specifically for UI work:

- **Remote endpoint** — pointing an app at a non-localhost `FRONTIER_CONNECT_ENDPOINT` requires explicit confirmation. A UI action can mutate prod data faster than a typoed curl.
- **No screenshots of secrets** — if the page being captured shows a token, API key, or other sensitive value, mask it or skip the screenshot. Screenshots land in `~/frontier-test/ui-screenshots/` with `chmod 600`. Note also that *snapshots* (not just screenshots) leak — see [chrome-devtools-mcp Tool Quirks](#chrome-devtools-mcp--tool-quirks-that-trip-the-skill) item 3.
- **No silent .env rewrites** — back up the file, change one line, show the diff.
- **PID identity** — Vite dev servers are `node` processes; confirm via `ps -p <PID> -o command=` that the command line includes the app path before killing.
