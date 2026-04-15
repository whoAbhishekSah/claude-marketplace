# Claude Marketplace

Claude Code plugins for Raystack services.

## Available Plugins

### frontier-sandbox

A Claude Code skill to setup and test [Frontier](https://github.com/raystack/frontier) RPCs locally. It can:

- **Setup Frontier from scratch** — provision PostgreSQL databases, start SpiceDB, build Frontier from source, run migrations, and start the server
- **Choose Docker or local deps** — defaults to Docker (one PG container with both the `frontier` and `frontier_spicedb` databases + a SpiceDB container, via a provided compose file). Fall back to fully-local install if you prefer
- **Auto-install dependencies** (local mode) — if PostgreSQL 15, SpiceDB v1.34.0, or Go 1.24+ aren't found, installs them locally without touching your global setup
- **Test RPCs** — make ConnectRPC calls with automatic authentication via mail OTP flow
- **Manage sessions** — cookie persistence, auto-login, super admin support
- **Rebuild & restart** — rebuild Frontier after code changes without recreating databases (skips rebuild if source unchanged)
- **Seed data** — create sample orgs, users, and projects for testing
- **View logs** — tail Frontier and SpiceDB logs for debugging
- **Proto-aware RPC discovery** — shows request/response fields and generates ready-to-use curl examples

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
| `status` | Show running processes, ports, and database info |
| `teardown` / `stop` | Stop services and optionally drop databases |
| `list rpcs` / `show rpcs` | List available RPCs with field details |
| `reconfigure` | Change server address, OTP, or PostgreSQL settings |

### Testing RPCs

Once running, you can ask things like:

- "List all users as super admin"
- "Create an organization called test-org"
- "Call GetOrganization with id xyz as user1@raystack.org"
- "Show me the fields for CreateProject"
- "Show me all available RPCs in AdminService"

The skill handles authentication automatically using test users on `raystack.org` domain.

### Test Users

| User | Type | Use for |
|------|------|---------|
| `user1@raystack.org` | Regular user | FrontierService RPCs |
| `user1+sa@raystack.org` | Super admin | AdminService + FrontierService RPCs |
| `admin1+sa@raystack.org` | Super admin (preconfigured) | Listed in config as platform admin |
| `admin2+sa@raystack.org` | Super admin (preconfigured) | Listed in config as platform admin |

**Super admin** = platform-level admin (from config, has AdminService access). **Org admin** = user with admin role in a specific org (FrontierService only).

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
      docker-compose.yaml          # PostgreSQL + SpiceDB dependencies (default setup)
      init-db.sql                  # Creates the second DB (frontier_spicedb) on first PG boot
    skills/
      frontier-sandbox/
        SKILL.md                   # Skill definition
```
