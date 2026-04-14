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
- **Sample Config Template**: `config/sample.config.yaml` (in this repo)

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

### Prerequisites Check

Verify these are available on the system before proceeding:
- **PostgreSQL** (check: `pg_isready` and `psql --version`) — must be running locally
- **SpiceDB CLI** v1.34.0 (check: `which spicedb && spicedb version`)
- **Go** >= 1.24.0 (check: `go version`)

If any prerequisite is missing, tell the user what to install and stop.

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

Copy the **sample config template** from `config/sample.config.yaml` in this repo to `~/frontier-test/config.yaml`.

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
3. Optionally drop the databases:
   ```bash
   dropdb -U <PG_USER> -h <PG_HOST> -p <PG_PORT> "frontier_<SUFFIX>"
   dropdb -U <PG_USER> -h <PG_HOST> -p <PG_PORT> "frontier_spicedb_<SUFFIX>"
   ```
4. Clean up `.config.json` by removing the setup-related keys

Always confirm with the user before dropping databases.

### Status Check

When the user asks for **status** of the local environment:

1. Check if SpiceDB process is running (using stored PID)
2. Check if Frontier process is running (using stored PID)
3. Check if PostgreSQL is accepting connections
4. Report the database names, ports, and PIDs

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
- `user1+sa@raystack.org` — superuser variant

**Only raystack.org users are supported for auto-login.** For real users, provide a cookie manually.

### Super Admin Users

To get a super admin session, add `+sa` alias to the email:
- Regular user: `user@raystack.org`
- Super admin: `user+sa@raystack.org`

### Cookie Rules

| Cookie Type | FrontierService | AdminService |
|-------------|-----------------|--------------|
| Admin cookie (superuser) | Yes | Yes |
| User cookie | Yes | No |

- AdminService requests require a superuser cookie (`+sa` email)
- If the user asks to call AdminService without specifying a superuser email, ask for one

## Usage

When the user wants to test an RPC:

1. Determine which email/user identity to use:
   - If the user specifies an email, use that
   - If context makes it clear (e.g., "as admin"), use the appropriate stored cookie
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

```bash
# List all RPCs in FrontierService
grep -E "^\s+rpc " ~/raystack/proton/raystack/frontier/v1beta1/frontier.proto

# List all RPCs in AdminService
grep -E "^\s+rpc " ~/raystack/proton/raystack/frontier/v1beta1/admin.proto
```
