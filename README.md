# Claude Marketplace

Claude Code plugins for Raystack services.

## Available Plugins

### frontier-sandbox

A Claude Code skill to setup and test [Frontier](https://github.com/raystack/frontier) locally — the **RPC layer** (ConnectRPC with auto-auth), the **UI layer** (client-demo + admin web apps driven through a real browser), and the **GitOps layer** (`frontier reconcile` against your local server).

**Backend / RPC:**

- **Setup Frontier from scratch** — provision PostgreSQL databases, start SpiceDB, build Frontier from source, run migrations, and start the server
- **Choose Docker or local deps** — defaults to Docker (one PG container with both the `frontier` and `frontier_spicedb` databases + a SpiceDB container, via a provided compose file). Fall back to fully-local install if you prefer
- **Auto-install dependencies** (local mode) — if PostgreSQL 15, SpiceDB v1.34.0, or Go 1.24+ aren't found, installs them locally without touching your global setup
- **Test RPCs** — make ConnectRPC calls with automatic authentication via mail OTP flow
- **Manage sessions** — cookie persistence, auto-login, platform admin support
- **Rebuild & restart** — rebuild Frontier after code changes without recreating databases (skips rebuild if source unchanged)
- **Seed data** — create sample orgs, users, and projects for testing
- **View logs** — tail Frontier and SpiceDB logs for debugging
- **Proto-aware RPC discovery** — shows request/response fields and generates ready-to-use curl examples

**UI (new in 2.0):**

- **Drive client-demo and admin** through a real browser via [chrome-devtools-mcp](https://github.com/ChromeDevTools/chrome-devtools-mcp) — click buttons, fill forms, navigate, assert on screen state (apps live at `web/apps/client-demo` and `web/apps/admin` in the Frontier repo)
- **Build and live-reload the Frontier JS SDK** — `pnpm install && pnpm run build` for the SDK, `pnpm run dev` for each app, with HMR for app source changes and a single `sdk rebuild` command for SDK changes
- **Manage each app's `.env`** — read `FRONTIER_CONNECT_ENDPOINT`, repoint an app to another deployment (`point client-demo to <url>`) with backup and remote-host confirmation
- **Real login flow** — drives the mailotp form just like a user, using the same `test_otp` and `+sa` conventions as the RPC flow

**GitOps (new in 2.2):**

Frontier now manages platform resources from a declarative file ([RFC 0001](https://github.com/raystack/frontier/blob/main/docs/rfcs/0001-declarative-reconcile.md)). The skill wraps that flow:

- **Runs `frontier reconcile` against your local server** — five kinds: `PlatformUser`, `Permission`, `Role`, `Preference`, `Webhook`
- **Asks once for your desired-state file** and remembers it in `.config.json`, so later runs don't ask again. Takes a single file, or a directory holding one file per kind — matched to kinds by their `kind:` field, then run in dependency order (permissions before roles)
- **Renders consul-template files** — a `.ctmpl` with escaped `{{` markers is rendered into a scratchpad copy first, never edited in place. A file with real `{{ with secret }}` directives stops the run instead of being guessed at
- **Always dry-runs first** — prints the plan verbatim, explains it in plain English, flags every removal, then asks before applying. Nothing is applied without a click
- **`export <kind>`** — dumps the live server state as a desired-state file, so you can seed a file that plans zero changes
- **`add superadmin <email>`** — backs up the file, appends the entry, dry-runs, applies, and clears the stale cookie
- **Handles the auth change** — `app.admin.users` is gone from the server config. Superadmins now come from the boot-seeded bootstrap service account plus whatever the reconcile file grants. The `+sa` suffix is only a naming convention now

## Installation

### Add the marketplace

```bash
/plugin marketplace add whoAbhishekSah/claude-marketplace
```

### Install the plugin

```bash
/plugin install frontier-sandbox@claude-marketplace
```

No need to pre-install dependencies. On startup the skill asks how to provision dependencies:

- **Docker** *(default)* — brings up PostgreSQL + SpiceDB with the compose file at `plugins/frontier-sandbox/config/docker-compose.yaml`. Both databases live in one PG container (created via an init script). You only need Docker and Go 1.24+ installed on the host.
- **Local** — installs PostgreSQL 15 and SpiceDB v1.34.0 into `~/frontier-test/bin/` (no impact on your global setup) and runs them as background processes.

Frontier itself is always built from source so you can iterate on code and use `rebuild` to restart.

## Usage

Run the skill in Claude Code:

```
/frontier-sandbox
```

On startup it will:
1. **Auto-detect** if Frontier and its dependencies (docker containers or local processes) are already running from a previous session and reuse them
2. Otherwise, ask whether to **setup Frontier** (and if so, docker or local mode — docker is the default) or **skip to testing** (if you have Frontier running elsewhere)

### Shorthand Commands

Once running, these work at any point in the conversation:

| Command | What it does |
|---------|-------------|
| `rebuild` / `restart` | Rebuild Frontier binary and restart the server |
| `logs` / `debug` | Show recent Frontier or SpiceDB logs |
| `seed` / `populate` | Create sample orgs, users, and projects |
| `reconcile` / `gitops` | Dry-run the desired-state file, show the plan, ask before applying |
| `dry run` / `plan` | Show the plan and stop |
| `apply` | Apply the plan (still shows it first) |
| `export <kind>` | Print live state as a desired-state file |
| `add superadmin <email>` | Add a platform admin to the file and reconcile it |
| `reconcile file` | Change the saved desired-state file path |
| `status` | Show running processes, ports, and database info |
| `teardown` / `stop` | Stop services and optionally drop databases |
| `list rpcs` / `show rpcs` | List available RPCs with field details |
| `ui` / `open ui` | List the two web apps with status, pick one to launch |
| `client-demo` / `open client-demo` | Build SDK (if needed), start client-demo, open in browser |
| `admin` / `open admin` | Build SDK (if needed), start admin, open in browser |
| `sdk rebuild` / `rebuild sdk` | Rebuild SDK and refresh any running app tabs |
| `ui status` | Show PID, port, and `FRONTIER_CONNECT_ENDPOINT` for each app |
| `ui stop` / `stop ui` | Stop the app dev servers (backend keeps running) |
| `point client-demo to <url>` | Rewrite that app's `FRONTIER_CONNECT_ENDPOINT` and restart |
| `reconfigure` | Change server address, OTP, or PostgreSQL settings |

### Testing RPCs

Once running, you can ask things like:

- "List all users as super admin"
- "Create an organization called test-org"
- "Call GetOrganization with id xyz as user1@raystack.org"
- "Show me the fields for CreateProject"
- "Show me all available RPCs in AdminService"

The skill handles authentication automatically using test users on `raystack.org` domain.

### UI Testing

Once you've run the backend (or pointed at an existing one), drive the apps through the browser:

- "open admin" — builds SDK, runs `pnpm dev`, opens the URL, drives the super-admin login (needs Frontier's HTTP gateway on `:8000` as well as ConnectRPC on `:8002`)
- "open client-demo" — same flow with a regular user
- "click the Create Organization button and name it acme"
- "go to Settings → Members and verify alice@raystack.org is listed"
- "I changed the SDK — sdk rebuild"
- "point client-demo to https://frontier.staging.example.com" (asks for confirmation since it's non-localhost)
- "ui status" — show what's running

**UI prerequisites** (the skill checks these on first UI command — it will NOT auto-install):

- [pnpm](https://pnpm.io) and Node.js 20+
- The [`chrome-devtools-mcp`](https://github.com/ChromeDevTools/chrome-devtools-mcp) plugin — install with `/plugin install chrome-devtools-mcp` (or equivalent), restart Claude Code
- The Frontier source cloned to `~/raystack/frontier` (the backend setup flow takes care of this)

### GitOps

Manage platform users, permissions, roles, preferences, and webhooks from a file:

- "reconcile" — the skill asks for your file or directory the first time, then remembers it
- "dry run" — show the plan without touching anything
- "add superadmin me+sa@raystack.org"
- "export platformuser" — write the current superadmins out as a file
- "reconcile ~/work/iam/platform-users.yaml" — one-off file, with an option to save it as the default

A `PlatformUser` file is the **full** access list. Anyone you leave out loses platform access. The skill spells out every removal in the plan before asking to apply.

Two host checks it makes before any apply: `localhost` alone doesn't mean local (a port-forward puts a shared server on a local port), and the file you picked and the `--host` you're pointed at are separate decisions — only the host decides what gets written.

### Test Users

| User | Type | Use for |
|------|------|---------|
| `user1@raystack.org` | Regular user | FrontierService RPCs |
| `user1+sa@raystack.org` | Regular user until reconciled | FrontierService RPCs; AdminService only after `add superadmin` |
| `admin1+sa@raystack.org` | Platform admin (in the sample reconcile file) | AdminService + FrontierService RPCs |
| bootstrap service account | Platform admin, seeded at boot | Basic auth for `reconcile` / `export`, and AdminService when no human admin exists |

**Platform admin** = has `relation: admin` in the `PlatformUser` reconcile file, or is the bootstrap service account. Has AdminService access. **Org admin** = user with an admin role in a specific org (FrontierService only).

The server no longer promotes emails from `app.admin.users` — that key is gone. A `+sa` email is an ordinary user until a reconcile run grants it admin.

### Safety

The skill includes several safety measures:
- **Remote host protection** — asks for confirmation before any action on non-localhost targets
- **Stale PID detection** — verifies process identity before killing
- **Graceful shutdown** — SIGTERM first, SIGKILL only after 5s timeout
- **Config backup** — backs up config.yaml before overwriting
- **Partial setup rollback** — cleans up on failure, with opt-out
- **File permissions** — chmod 600 on files containing secrets
- **Database name verification** — double-checks before dropping databases
- **Health check timeout** — 30s timeout with log output on failure
- **Never applies a reconcile blind** — dry run first, plan shown verbatim, removals called out, explicit click to apply
- **Desired-state file backups** — any edit to your reconcile file is backed up first and the diff is shown

## Repository Structure

```
.claude-plugin/
  marketplace.json                 # Marketplace catalog
plugins/
  frontier-sandbox/
    .claude-plugin/
      plugin.json                  # Plugin manifest
    config/
      sample.config.yaml           # Frontier config template (no secrets)
      sample.platform-users.yaml   # Starter desired-state file for `frontier reconcile`
      docker-compose.yaml          # PostgreSQL + SpiceDB dependencies (default setup)
      init-db.sql                  # Creates the second DB (frontier_spicedb) on first PG boot
    skills/
      frontier-sandbox/
        SKILL.md                   # Skill definition (RPC + UI + GitOps flows)
```

## Versions

- **2.2.0** — adds the GitOps layer from [RFC 0001](https://github.com/raystack/frontier/blob/main/docs/rfcs/0001-declarative-reconcile.md). New `reconcile` / `dry run` / `apply` / `export` / `add superadmin` commands that run against the local server, with a mandatory dry run and an explicit apply confirmation. The desired-state location is asked once and saved in `.config.json` — a single file, or a directory of per-kind files run in dependency order. Handles consul-template `.ctmpl` sources by rendering a scratchpad copy. Drops `app.admin.users` from the config template (the server no longer reads it) and replaces it with the `app.admin.bootstrap` service account, whose credentials are generated at setup and stored in `.config.json`. Cookie store and mailotp auto-login are unchanged.
- **2.1.0** — switches every decision point to Claude Code's `AskUserQuestion` picker (radio buttons / multi-select with descriptions) instead of prose questions. Adds a top-level "User Interaction Style" section and concrete picker templates at 14 decision points: startup action, setup mode, port conflict, Docker prereqs fallback, health-check failure, teardown scope (Docker / UI / everything), remote-host confirmation, seed conflicts, app selection (`ui`), path-discovery folder ambiguity, `point <app> to <url>` confirmation, and Frontier role mapping.
- **2.0.1** — corrections from a real end-to-end UI session: admin folder is `admin` not `admin-app`; admin uses two `.env` endpoint keys; documented chrome-devtools-mcp tool quirks (uid drift, sparse default snapshots, secret leakage via `wait_for`, dropdown-then-button click misroute, drill-into-detail for destructive actions); added Frontier role-name mapping (no "Admin" role — use "Organization Manager"); captured the real login route `/magiclink-verify`
- **2.0.0** — adds UI testing for client-demo and admin via chrome-devtools-mcp, with SDK rebuild loop and `.env` endpoint management
- **1.0.0** — initial release: RPC testing, Docker/local backend setup, auto-auth, seed data
