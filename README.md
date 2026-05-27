
# QuestDB client for Julia

This package provides a Julia client for [QuestDB](https://questdb.io/), a high-performance time-series database.

# Installation

The package can be installed using the Julia package manager:

```julia
] add QuestDB
```

or 

```julia
using Pkg
Pkg.add("QuestDB")
```

# Usage

The package provides a high-level API for interacting with QuestDB. The API is designed to be as simple as possible, while still providing the functionality required to work with time-series data. The package also provides a low-level API for interacting with the C library directly.

## Examples

The following examples show how to use the package to interact with QuestDB. For more examples, see the [examples](examples) directory.

```julia

using .QuestDB
using Dates

auth = (
    "testUser1",                                    # kid
    "5UjEMuA0Pj5pjK8a-fa24dyIf-Es5mYny3oE_Wmus48",  # d
    "fLKYEaoEb9lrn3nkwLDA-M_xnuFOdSt9y0Z7_vWSHLU",  # x
    "Dt5tbS1dEDMSYfym3fgMv0B99szno-dFc1rYF9t0aac"   # y
)  

sender = Sender("localhost", 9009, auth)

try                      
    sender.table("testing_OOP2")
    sender.symbol("first_symbol", "first_symbol")
    sender.column("column_a", "value_a")
    sender.column("column_b_int", 1)
    sender.column("column_c_float", 1.1)
    sender.column("column_d_bool", true)
    sender.column("timestamp_column", Dates.Microsecond(1674983677000000))            
    sender.flush()
catch e
    println(e)
finally
    sender.close()
end
```

# Docs

The documentation for the package can be found [here](https://questdb.github.io/QuestDB.jl). The documentation is automatically generated using Documenter.jl.

# Community

If you need help, have additional questions or want to provide feedback, you may find us on Slack.

You can also sign up to our mailing list to get notified of new releases.

# License
The code is released under the Apache License 2.0.

---

# IENAI fork notes

## Cargo.lock override (technical debt)

The `c-questdb-client` submodule tracks upstream
[`questdb/c-questdb-client`](https://github.com/questdb/c-questdb-client) at
tag `6.0.0`. Upstream ships a `questdb-rs-ffi/Cargo.lock` that pins old
transitive Rust dependencies with public CVEs (e.g. `rustls-webpki 0.103.6`,
`bytes 1.10.1`, `rand 0.9.2`).

Rather than maintaining a parallel fork of `c-questdb-client` just to bump a
lockfile, we keep the submodule pointing at vanilla upstream and apply our
own lockfile at build time via `Make.jl`:

1. `patches/questdb-rs-ffi-Cargo.lock` is the IENAI-curated lockfile (deps
   bumped to the most recent semver-compatible versions known to be
   CVE-free).
2. `Make.jl :: apply_lockfile_override()` copies that file over the
   submodule's `Cargo.lock` immediately before `cargo build --release --locked`.

### Refreshing the patch

When the submodule is bumped to a new upstream tag OR when new CVEs land
against transitive deps, regenerate the patch:

```bash
# From the repo root
cd c-questdb-client/questdb-rs-ffi
cargo update                      # updates Cargo.lock in place
cp Cargo.lock ../../patches/questdb-rs-ffi-Cargo.lock
cd ../..
git checkout -- c-questdb-client  # discard the in-submodule edit
```

Commit the updated `patches/questdb-rs-ffi-Cargo.lock`. Renovate / Dependabot
can be wired to do this automatically by treating that file as a regular
`Cargo.lock`.

### When this debt can be paid down

This override exists because we don't currently maintain an IENAI fork of
`c-questdb-client`. The day we either (a) take over the submodule with our
own fork, or (b) upstream accepts a PR to refresh `Cargo.lock`, the override
can be deleted and `Make.jl :: apply_lockfile_override()` removed.