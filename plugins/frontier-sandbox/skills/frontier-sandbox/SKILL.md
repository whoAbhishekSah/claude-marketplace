# Frontier Local Testing

Test Frontier RPCs locally using ConnectRPC protocol with automatic authentication.
Optionally includes full local setup of Frontier with all dependencies (PostgreSQL, SpiceDB).

## Configuration

- **Working Directory**: `~/frontier-test` (create if missing)
- **Frontier Source**: Cloned from `https://github.com/raystack/frontier`
- **Proto Definitions**: `~/raystack/proton/raystack/frontier/v1beta1/`
- **Cookie Store**: `~/frontier-test/.cookies.json`
- **Config Store**: `~/frontier-test/.config.json`
- **Generated Frontier Config**: `~/frontier-test/config.yaml`
- **Sample Config Template**: `plugins/frontier-sandbox/config/sample.config.yaml` (in this repo)

---

## Startup Behavior

On startup, do NOT print cookies or check env vars.

**Ask the user one question first:**

> Would you like to:
> 1. **Setup Frontier locally** — install dependencies, create databases, build and start the server
> 2. **Skip to testing** — I already have Frontier running, just help me test RPCs

- If the user picks **1**, go to [Local Environment Setup](#local-environment-setup)
- If the user picks **2**, go to [First-time Config](#first-time-config) (just collect server address and OTP), then proceed to [Usage](#usage)

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

---

## Local Environment Setup

When the user chooses to setup Frontier locally, follow these steps. This sets up PostgreSQL databases, SpiceDB, builds Frontier, and starts it.

First collect the [First-time Config](#first-time-config) values, plus these additional details:

3. **PostgreSQL user** (default: current OS username from `whoami`)
4. **PostgreSQL password** (default: empty — for local trust auth)
5. **PostgreSQL host** (default: `localhost`)
6. **PostgreSQL port** (default: `5432`)

Update `.config.json` with the full set:
```json
{
  "server": "localhost:8002",
  "test_domain": "raystack.org",
  "test_otp": "hemlo",
  "pg_user": "abhishek",
  "pg_password": "",
  "pg_host": "localhost",
  "pg_port": "5432"
}
```

### Remote Host Safety Check

If `pg_host` or `server` is **not** `localhost` / `127.0.0.1`, the user is pointing at a remote or shared environment. Before performing any destructive or state-changing action (creating databases, dropping databases, running migrations, starting/stopping services, seeding data), **always ask the user for explicit confirmation** with the exact action and target host. Do NOT proceed silently against remote hosts.

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
2. Offer options:
   - **Kill the existing process** — if it looks like a stale Frontier/SpiceDB from a previous run
   - **Use alternate ports** — pick free ports and update the config accordingly. If using alternate ports, update `spicedb_port` in `.config.json` and the `app.connect.port` / `spicedb.port` / `app.metrics_port` in the generated config.yaml
3. Do NOT silently fail or overwrite a running service

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

### Step 5: Generate Frontier config.yaml

Copy the **sample config template** from `plugins/frontier-sandbox/config/sample.config.yaml` in this repo to `~/frontier-test/config.yaml`.

Replace the placeholders with actual values:
- `<HASH_SECRET_KEY>` — generate a random 32-char hex string: `openssl rand -hex 16`
- `<BLOCK_SECRET_KEY>` — generate a different random 32-char hex string: `openssl rand -hex 16`
- `<TEST_OTP>` — from `.config.json`
- `<PG_USER>` — from `.config.json`
- `<PG_PASSWORD>` — from `.config.json` (empty string if none)
- `<PG_HOST>` — from `.config.json`
- `<PG_PORT>` — from `.config.json`
- `<FRONTIER_DB>` — e.g., `frontier_a3f1`
- `<SPICEDB_PORT>` — `50052`

Do NOT hardcode the secret keys. Generate fresh ones each setup.

### Step 6: Clone and Build Frontier

If Frontier source is not already present at `~/raystack/frontier`, clone it:
```bash
git clone https://github.com/raystack/frontier ~/raystack/frontier
```

Build:
```bash
cd ~/raystack/frontier && CGO_ENABLED=0 go build -o ~/frontier-test/frontier .
```

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

### Teardown

When the user asks to **stop**, **teardown**, or **cleanup** the local environment:

1. Kill Frontier process (using stored `frontier_pid`)
2. Kill SpiceDB process (using stored `spicedb_pid`)
3. If a local PostgreSQL was started (`pg_data_dir` exists in `.config.json`), stop it:
   ```bash
   <bin_pg_ctl> -D ~/frontier-test/pgdata stop
   ```
4. Optionally drop the databases (use resolved `bin_dropdb` path):
   ```bash
   <bin_dropdb> -U <PG_USER> -h <PG_HOST> -p <PG_PORT> "frontier_<SUFFIX>"
   <bin_dropdb> -U <PG_USER> -h <PG_HOST> -p <PG_PORT> "frontier_spicedb_<SUFFIX>"
   ```
5. Clean up `.config.json` by removing the setup-related keys

Always confirm with the user before dropping databases.

### Status Check

When the user asks for **status** of the local environment:

1. Check if SpiceDB process is running (using stored PID)
2. Check if Frontier process is running (using stored PID)
3. Check if PostgreSQL is accepting connections
4. Report the database names, ports, and PIDs

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
Login as `admin1+sa@raystack.org` using the auto-login flow.

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

The user can ask to seed at any time. If data already exists (org name conflict), skip and report which items were skipped.

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
- `user1+sa@raystack.org` — super admin variant

**Only raystack.org users are supported for auto-login.** For real users, provide a cookie manually.

### Super Admin vs Org Admin

There are two kinds of "admin" in Frontier — don't confuse them:

- **Super admin** (platform-level): Listed in `app.admin.users` in config.yaml. Has access to both FrontierService and AdminService. Created by adding `+sa` alias to the email (e.g., `admin1+sa@raystack.org`).
- **Org admin** (org-level): A regular user who has been granted an admin/owner role within a specific organization. Can manage that org via FrontierService but has NO AdminService access.

To get a super admin session, add `+sa` alias to the email:
- Regular user: `user@raystack.org`
- Super admin: `user+sa@raystack.org`

### Cookie Rules

| Cookie Type | FrontierService | AdminService |
|-------------|-----------------|--------------|
| Super admin cookie (`+sa` email) | Yes | Yes |
| Regular user cookie | Yes | No |

- **Super admin** = users listed in `app.admin.users` in config.yaml (e.g., `admin1+sa@raystack.org`). These are platform-level admins with access to AdminService.
- **Org admin** = users who have the admin/owner role within a specific organization. They can manage that org via FrontierService but do NOT have AdminService access.
- AdminService requests require a **super admin** cookie (`+sa` email)
- If the user asks to call AdminService without specifying a super admin email, ask for one

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
