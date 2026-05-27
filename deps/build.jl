# This file is executed by Julia's Pkg system on `Pkg.build("QuestDB")` and
# automatically as part of `Pkg.instantiate()` the first time the package is
# installed (whether via path-develop, registry, or `Pkg.add`).
#
# It produces the native libquestdb_client.{so,dylib,dll} that LibQuestDB.jl
# loads at runtime. We bypass the JLL-distributed binary (which is 3 years
# stale, ships unpatched Rust deps, and is no longer maintained upstream) by
# compiling from source against the c-questdb-client submodule pinned in this
# repo, with our Cargo.lock override on top.
#
# See README.md → "IENAI fork notes" for the long-form rationale.

include(joinpath(@__DIR__, "..", "Make.jl"))

build()
