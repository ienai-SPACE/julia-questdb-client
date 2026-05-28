# Make.jl serves two roles:
#   1. As a script:  `julia Make.jl build`  (CLI workflow, used during dev)
#   2. As a library: `include("Make.jl")` from deps/build.jl  (Pkg integration)
#
# The CLI block is gated at the bottom so `include()` does not auto-run
# ArgParse, which is otherwise installed via Pkg and that side-effect must
# not happen during a package build.


questdb_rs_ffi_dir = joinpath(@__DIR__, "c-questdb-client", "questdb-rs-ffi")
patched_lockfile  = joinpath(@__DIR__, "patches", "questdb-rs-ffi-Cargo.lock")


"""
    apply_lockfile_override()

Overwrite the Cargo.lock that ships with the upstream c-questdb-client
submodule with our IENAI-curated copy under `patches/`. The upstream lockfile
pins old transitive Rust deps (`rustls-webpki 0.103.6`, `bytes 1.10.1`,
`rand 0.9.2`, etc.) with public CVEs. Rather than maintaining a parallel fork
of questdb/c-questdb-client just to bump a lockfile, we keep the submodule
pointing at upstream `6.0.0` and apply this override at build time.

See README.md → "Cargo.lock override" for the long-form rationale and the
process for refreshing the patch.
"""
function apply_lockfile_override()
    isfile(patched_lockfile) || error("Patched lockfile not found: $patched_lockfile")
    target = joinpath(questdb_rs_ffi_dir, "Cargo.lock")
    cp(patched_lockfile, target, force = true)
    @info "Applied Cargo.lock override" from=patched_lockfile to=target
end


function build()
    apply_lockfile_override()
    # --locked refuses to silently rewrite the lockfile if Cargo.toml has drifted
    # away from our patched lockfile — catches the case where upstream c-questdb-client
    # bumped a dep and our override is out of date.
    cargo_build = Cmd(
        `cargo build --release --locked`,
        dir = questdb_rs_ffi_dir)
    run(cargo_build)

    target_dir = joinpath(questdb_rs_ffi_dir, "target", "release")
    name = "questdb_client"

    ## TODO: There needs to be some OS-specific logic here to copy the
    ## Correct library file to the correct location.

    if Sys.iswindows()
        lib_prefix = ""  # TODO needs to be "" on Windows.    
        lib_suffix = ".dll"
    elseif Sys.islinux()
        lib_prefix = "lib" 
        lib_suffix = ".so" 
    elseif Sys.isapple()
        lib_prefix = "lib" 
        lib_suffix = ".dylib"
    end
    
    lib_name = lib_prefix * name * lib_suffix
    lib_path = joinpath(target_dir, lib_name)

    # Copy the lib to its final destination. force=true so re-runs after a
    # rebuild overwrite the previous .so instead of erroring out.
    cp(lib_path, joinpath(@__DIR__, "src", lib_name); force = true)
end


function clean()
    cargo_clean = Cmd(
        `cargo clean`,
        dir = questdb_rs_ffi_dir)
    run(cargo_clean)
end


function sync_submodule()
    git_submodule_update = Cmd(
        `git submodule update --init --recursive`,
        dir = @__DIR__)
    run(git_submodule_update)
end


# CLI entry point — only runs when this file is invoked directly via
#   julia Make.jl <command>
# When included from deps/build.jl or any other Julia code, this block is
# skipped. We deliberately avoid ArgParse here: Julia expands macros at the
# parse time of the enclosing block, before the `using ArgParse` inside the
# same `if` has executed, which would crash `include("Make.jl")` from
# deps/build.jl with `UndefVarError: @add_arg_table`. Three commands do not
# need argument-parsing machinery anyway.
if abspath(PROGRAM_FILE) == @__FILE__
    command = isempty(ARGS) ? "" : ARGS[1]
    if command == "build"
        build()
    elseif command == "clean"
        clean()
    elseif command == "sync_submodule"
        sync_submodule()
    else
        println(stderr, "Usage: julia Make.jl <build|clean|sync_submodule>")
        exit(1)
    end
end
