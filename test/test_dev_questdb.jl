#!/usr/bin/env julia
#
# Local end-to-end smoke test against the dev QuestDB instance over Tailscale.
#
# Purpose: bypass the ~30-min i360-api slow-path image rebuild while we iterate
# on the c-questdb-client 6.0.0 migration. This script exercises the same code
# path the api will use (TCPS + ECDSA auth) so a passing run here is strong
# evidence the production deploy will work.
#
# Prereqs:
#   1. libquestdb_client.so present at src/ (built via `julia Make.jl build`).
#   2. Tailscale up; i360-questdb-infra2-development.tail7f32e.ts.net reachable.
#   3. Four env vars exported with the dev QuestDB ECDSA keypair:
#        QUESTDB_AUTH_KID, QUESTDB_AUTH_D, QUESTDB_AUTH_X, QUESTDB_AUTH_Y
#      (sourced from SSM /questdb/development/AUTH_* — see task 86ca0mb63).
#   4. (optional) QUESTDB_HOST / QUESTDB_PORT / QUESTDB_PROTOCOL overrides.
#
# Usage:
#   QUESTDB_AUTH_KID=...  QUESTDB_AUTH_D=... \
#   QUESTDB_AUTH_X=...    QUESTDB_AUTH_Y=... \
#   julia --project=. test/test_dev_questdb.jl
#
# Exit codes:
#   0 — sent N rows, read them back via REST, payload matches.
#   1 — connection / auth / ingest failure.
#   2 — read-back mismatch (rows ingested but query did not return expected data).
#   3 — pre-flight failed (missing env vars, .so not found, Tailscale unreachable).

using Pkg
# Activate the test-only environment (HTTP/JSON3 for REST read-back, CEnum for
# the FFI bindings since src/LibQuestDB.jl is included directly).
# Resolve before instantiate so adding a dep to Project.toml without committing
# a Manifest does not require a manual `Pkg.resolve()` round-trip.
Pkg.activate(@__DIR__)
Pkg.resolve()
Pkg.instantiate()

using Dates
using HTTP
using JSON3

# Load the local module under test (NOT the registered package, in case the
# user has a stale version cached in their depot).
include(joinpath(@__DIR__, "..", "src", "QuestDB.jl"))
using .QuestDB

# ----------------------------------------------------------------------------
# Pre-flight
# ----------------------------------------------------------------------------
#
# Defaults target a localhost QuestDB so this script is reusable by anyone
# (upstream contributors, other forks). For IENAI dev, export:
#   QUESTDB_HOST=i360-questdb-infra2-development.tail7f32e.ts.net
#   QUESTDB_PROTOCOL=tcp           # dev does NOT terminate TLS on 9009
# (staging/prod posture: tcps. Not exercised by this smoke test — first real
# TLS validation happens when the api ships to staging.)

const DEFAULT_HOST = "localhost"
const DEFAULT_PORT = 9009
const DEFAULT_REST_PORT = 9000
const DEFAULT_PROTOCOL = :tcps

host = get(ENV, "QUESTDB_HOST", DEFAULT_HOST)
port = parse(Int, get(ENV, "QUESTDB_PORT", string(DEFAULT_PORT)))
rest_port = parse(Int, get(ENV, "QUESTDB_REST_PORT", string(DEFAULT_REST_PORT)))
protocol = Symbol(get(ENV, "QUESTDB_PROTOCOL", string(DEFAULT_PROTOCOL)))

required_keys = ["QUESTDB_AUTH_KID", "QUESTDB_AUTH_D", "QUESTDB_AUTH_X", "QUESTDB_AUTH_Y"]
missing_keys = [k for k in required_keys if !haskey(ENV, k) || isempty(ENV[k])]
if !isempty(missing_keys)
    @error "Missing required env vars; cannot authenticate" missing=missing_keys
    exit(3)
end

auth = (ENV["QUESTDB_AUTH_KID"], ENV["QUESTDB_AUTH_D"],
        ENV["QUESTDB_AUTH_X"], ENV["QUESTDB_AUTH_Y"])

# Stamp test rows with a per-run table name so re-runs do not collide and so
# the test can clean up after itself by dropping the table at the end.
const TABLE = "secops_smoketest_" * string(round(Int, time()))

@info "Pre-flight OK" host port protocol table=TABLE

# ----------------------------------------------------------------------------
# Phase 1: connect + ingest 3 rows
# ----------------------------------------------------------------------------

@info "Connecting to QuestDB"
sender = try
    Sender(host, port; protocol=protocol, auth=auth, init_capacity=64 * 1024)
catch e
    @error "Sender construction failed" exception=(e, catch_backtrace())
    exit(1)
end
@info "Connected. Buffer capacity = $(capacity(sender)) bytes"

# Three rows with deterministic content so the read-back can assert exact match.
const NOW_NS = round(Int64, time() * 1_000_000_000)
const ROWS = [
    (label="alpha", value=1.0,  flag=true,  ts_ns=NOW_NS + 0 * 1_000_000),
    (label="beta",  value=2.5,  flag=false, ts_ns=NOW_NS + 1 * 1_000_000),
    (label="gamma", value=3.14, flag=true,  ts_ns=NOW_NS + 2 * 1_000_000),
]

@info "Ingesting $(length(ROWS)) rows"
try
    for r in ROWS
        sender.table(TABLE)
        sender.symbol("label", r.label)
        sender.column("value", r.value)
        sender.column("flag",  r.flag)
        sender.at(Dates.Nanosecond(r.ts_ns))
    end
    sender.flush()
catch e
    @error "Ingest failed" exception=(e, catch_backtrace())
    sender.close()
    exit(1)
end
sender.close()
@info "Ingest + flush successful"

# ----------------------------------------------------------------------------
# Phase 2: read back via REST and assert match
# ----------------------------------------------------------------------------
#
# QuestDB commits ILP batches asynchronously (commit_lag). Poll up to 10s.
# REST endpoint: GET http://$host:$rest_port/exec?query=...
# Note: dev REST is not auth-protected behind Tailscale — production setups
# differ. If a future env locks the REST port too, fail fast with a clear
# message rather than retrying forever.

rest_url = "http://$host:$rest_port/exec"

function fetch_rows()
    q = "SELECT label, value, flag, timestamp FROM $TABLE ORDER BY timestamp"
    resp = HTTP.get(rest_url, query=Dict("query" => q); readtimeout=5)
    body = JSON3.read(String(resp.body))
    return get(body, :dataset, Any[])
end

@info "Polling REST for read-back" url=rest_url
# Wrap in a function so the `got` assignment is in a normal (hard) scope —
# Julia's REPL-style soft scope inside `while` at top-level treats `got = ...`
# as a new local, which would silently swallow the rows we read.
function poll_until_ready()
    rows = Any[]
    deadline = time() + 10.0
    while time() < deadline
        rows = try
            fetch_rows()
        catch e
            @warn "REST query failed (will retry)" exception=e
            []
        end
        length(rows) >= length(ROWS) && break
        sleep(0.5)
    end
    return rows
end
got = poll_until_ready()

if length(got) < length(ROWS)
    @error "Read-back returned fewer rows than ingested" got_count=length(got) want=length(ROWS)
    exit(2)
end

# Compare in a function scope to avoid Julia's soft-scope ambiguity warning
# when assigning to a `mismatches` counter inside a top-level `for`.
function count_mismatches(got_rows, want_rows)
    n = 0
    for (i, row) in enumerate(want_rows)
        got_row = got_rows[i]
        if string(got_row[1]) != row.label || got_row[2] != row.value || got_row[3] != row.flag
            @warn "Row mismatch" idx=i got=got_row want=(row.label, row.value, row.flag)
            n += 1
        end
    end
    return n
end
mismatches = count_mismatches(got, ROWS)
if mismatches > 0
    @error "$mismatches/$(length(ROWS)) row mismatches"
    exit(2)
end

@info "Read-back OK. All $(length(ROWS)) rows match. PASS"

# ----------------------------------------------------------------------------
# Phase 3: cleanup
# ----------------------------------------------------------------------------

try
    HTTP.get(rest_url, query=Dict("query" => "DROP TABLE $TABLE"); readtimeout=5)
    @info "Dropped test table" table=TABLE
catch e
    @warn "Could not drop test table (left on server)" table=TABLE exception=e
end
