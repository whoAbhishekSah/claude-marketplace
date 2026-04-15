-- Runs once on first Postgres container start (via /docker-entrypoint-initdb.d).
-- The 'frontier' database is already created by POSTGRES_DB in docker-compose.yaml.
-- This file adds the second database used by SpiceDB, so both live in one PG container.

CREATE DATABASE frontier_spicedb;
GRANT ALL PRIVILEGES ON DATABASE frontier_spicedb TO frontier;
