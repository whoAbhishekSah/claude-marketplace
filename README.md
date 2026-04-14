# Claude Marketplace

Claude Code plugins for Raystack services.

## Available Plugins

### frontier-sandbox

A Claude Code skill to setup and test [Frontier](https://github.com/raystack/frontier) RPCs locally. It can:

- **Setup Frontier from scratch** — provision PostgreSQL databases, start SpiceDB, build Frontier from source, run migrations, and start the server
- **Test RPCs** — make ConnectRPC calls with automatic authentication via mail OTP flow
- **Manage sessions** — cookie persistence, auto-login, superadmin support

## Installation

### Prerequisites

If you plan to setup Frontier locally (not required if you already have a running instance):

- **PostgreSQL 15+** — running locally
- **SpiceDB CLI v1.34.0** — `brew install authzed/tap/spicedb` or see [SpiceDB releases](https://github.com/authzed/spicedb/releases/tag/v1.34.0)
- **Go 1.24+** — for building Frontier from source

### Add the marketplace

```bash
/plugin marketplace add whoAbhishekSah/claude-marketplace
```

### Install the plugin

```bash
/plugin install frontier-sandbox@claude-marketplace
```

## Usage

Run the skill in Claude Code:

```
/frontier-sandbox
```

You'll be asked whether to:

1. **Setup Frontier locally** — walks you through database creation, SpiceDB setup, building and starting the server
2. **Skip to testing** — if you already have Frontier running somewhere, jump straight to making RPC calls

### Testing RPCs

Once running, you can ask things like:

- "List all users as admin"
- "Create an organization called test-org"
- "Call GetOrganization with id xyz as user1@raystack.org"
- "Show me all available RPCs in AdminService"

The skill handles authentication automatically using test users on `raystack.org` domain.

### Test Users

| User | Type | Example |
|------|------|---------|
| `user1@raystack.org` | Regular user | For standard FrontierService RPCs |
| `user1+sa@raystack.org` | Super admin | For AdminService RPCs |
| `admin1+sa@raystack.org` | Super admin (preconfigured) | Listed in config as admin |
| `admin2+sa@raystack.org` | Super admin (preconfigured) | Listed in config as admin |

### Managing the Local Environment

- Ask for **status** to see running processes and database info
- Ask to **stop** or **teardown** to kill processes and optionally drop databases

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
    skills/
      frontier-sandbox/
        SKILL.md                   # Skill definition
```
