module LibQuestDB

using CEnum

# Path to the libquestdb_client native library built from source by Make.jl
# (invoked via deps/build.jl during Pkg.build / Pkg.instantiate). We bypass
# the upstream c_questdb_client_jll because it has not been re-published
# since 2023-02 and ships unpatched Rust transitive deps with public CVEs.
# See README.md → "IENAI fork notes" for the long-form rationale.
const libquestdb_client = let
    libname = if Sys.iswindows()
        "questdb_client.dll"
    elseif Sys.isapple()
        "libquestdb_client.dylib"
    else
        "libquestdb_client.so"
    end
    joinpath(@__DIR__, libname)
end

function __init__()
    if !isfile(libquestdb_client)
        error("""
              libquestdb_client native library not found at $(libquestdb_client).
              Run `Pkg.build("QuestDB")` (or `julia Make.jl build` for a manual
              rebuild). The library is produced by compiling
              c-questdb-client/questdb-rs-ffi via cargo and copied into src/.
              """)
    end
end

"""
    line_sender_utf8

Non-owning validated UTF-8 encoded string. The string need not be null-terminated.
"""
struct line_sender_utf8
    len::Csize_t
    buf::Ptr{Cchar}
end


"""
    line_sender_utf8_assert(len, buf)

Construct a UTF-8 object from UTF-8 encoded buffer and length. If the passed in buffer is not valid UTF-8, the program will abort.

### Parameters
* `len`:\\[in\\] Length in bytes of the buffer.
* `buf`:\\[in\\] UTF-8 encoded buffer.
"""
function line_sender_utf8_assert(len, buf)
    ccall((:line_sender_utf8_assert, libquestdb_client), line_sender_utf8, (Csize_t, Ptr{Cchar}), len, buf)
end

"""
    line_sender_table_name

Non-owning validated table, symbol or column name. UTF-8 encoded. Need not be null-terminated.
"""
struct line_sender_table_name
    len::Csize_t
    buf::Ptr{Cchar}
end

"""
    line_sender_table_name_assert(len, buf)

Construct a table name object from UTF-8 encoded buffer and length. If the passed in buffer is not valid UTF-8, or is not a valid table name, the program will abort.

### Parameters
* `len`:\\[in\\] Length in bytes of the buffer.
* `buf`:\\[in\\] UTF-8 encoded buffer.
"""
function line_sender_table_name_assert(len, buf)
    ccall((:line_sender_table_name_assert, libquestdb_client), line_sender_table_name, (Csize_t, Ptr{Cchar}), len, buf)
end

"""
    line_sender_column_name

Non-owning validated table, symbol or column name. UTF-8 encoded. Need not be null-terminated.
"""
struct line_sender_column_name
    len::Csize_t
    buf::Ptr{Cchar}
end

"""
    line_sender_column_name_assert(len, buf)

Construct a column name object from UTF-8 encoded buffer and length. If the passed in buffer is not valid UTF-8, or is not a valid column name, the program will abort.

### Parameters
* `len`:\\[in\\] Length in bytes of the buffer.
* `buf`:\\[in\\] UTF-8 encoded buffer.
"""
function line_sender_column_name_assert(len, buf)
    ccall((:line_sender_column_name_assert, libquestdb_client), line_sender_column_name, (Csize_t, Ptr{Cchar}), len, buf)
end

mutable struct line_sender_error end

"""
    line_sender_error_code

Category of error.
"""
@cenum line_sender_error_code::UInt32 begin
    line_sender_error_could_not_resolve_addr = 0
    line_sender_error_invalid_api_call = 1
    line_sender_error_socket_error = 2
    line_sender_error_invalid_utf8 = 3
    line_sender_error_invalid_name = 4
    line_sender_error_invalid_timestamp = 5
    line_sender_error_auth_error = 6
    line_sender_error_tls_error = 7
end

"""
    line_sender_error_get_code(arg1)

Error code categorizing the error.
"""
function line_sender_error_get_code(arg1)
    ccall((:line_sender_error_get_code, libquestdb_client), line_sender_error_code, (Ptr{line_sender_error},), arg1)
end

"""
    line_sender_error_msg(arg1, len_out)

UTF-8 encoded error message. Never returns NULL. The `len_out` argument is set to the number of bytes in the string. The string is NOT null-terminated.
"""
function line_sender_error_msg(arg1, len_out)
    ccall((:line_sender_error_msg, libquestdb_client), Ptr{Cchar}, (Ptr{line_sender_error}, Ptr{Csize_t}), arg1, len_out)
end

"""
    line_sender_error_free(arg1)

Clean up the error.
"""
function line_sender_error_free(arg1)
    ccall((:line_sender_error_free, libquestdb_client), Cvoid, (Ptr{line_sender_error},), arg1)
end

"""
    line_sender_utf8_init(str, len, buf, err_out)

Check the provided buffer is a valid UTF-8 encoded string.

### Parameters
* `str`:\\[out\\] The object to be initialized.
* `len`:\\[in\\] Length in bytes of the buffer.
* `buf`:\\[in\\] UTF-8 encoded buffer. Need not be null-terminated.
* `err_out`:\\[out\\] Set on error.
### Returns
true on success, false on error.
"""
function line_sender_utf8_init(str, len, buf, err_out) 
    ccall((:line_sender_utf8_init, libquestdb_client), Bool, (Ptr{line_sender_utf8}, Csize_t, Ptr{Cchar}, Ptr{Ptr{line_sender_error}}), str, len, buf, err_out)   
end

"""
    line_sender_table_name_init(name, len, buf, err_out)

Check the provided buffer is a valid UTF-8 encoded string that can be used as a table name.

### Parameters
* `name`:\\[out\\] The object to be initialized.
* `len`:\\[in\\] Length in bytes of the buffer.
* `buf`:\\[in\\] UTF-8 encoded buffer. Need not be null-terminated.
* `err_out`:\\[out\\] Set on error.
### Returns
true on success, false on error.
"""
function line_sender_table_name_init(name, len, buf, err_out)
    ccall((:line_sender_table_name_init, libquestdb_client), Bool, (Ptr{line_sender_table_name}, Csize_t, Ptr{Cchar}, Ptr{Ptr{line_sender_error}}), name, len, buf, err_out)
end

"""
    line_sender_column_name_init(name, len, buf, err_out)

Check the provided buffer is a valid UTF-8 encoded string that can be used as a symbol name or column name.

### Parameters
* `name`:\\[out\\] The object to be initialized.
* `len`:\\[in\\] Length in bytes of the buffer.
* `buf`:\\[in\\] UTF-8 encoded buffer. Need not be null-terminated.
* `err_out`:\\[out\\] Set on error.
### Returns
true on success, false on error.
"""
function line_sender_column_name_init(name, len, buf, err_out)
    ccall((:line_sender_column_name_init, libquestdb_client), Bool, (Ptr{line_sender_column_name}, Csize_t, Ptr{Cchar}, Ptr{Ptr{line_sender_error}}), name, len, buf, err_out)
end

mutable struct line_sender_buffer end

"""
    line_sender_buffer_new(version) -> Ptr{line_sender_buffer}

Create a buffer for serializing ILP messages, pinned to `version` (a
LINE_SENDER_PROTOCOL_VERSION_* enum). In c-questdb-client 6.0.0 the buffer
encoder picks per-column wire format based on this version (e.g. v1 emits
f64 as text, v2 emits binary). The sender will refuse a flush if the
buffer's version does not match the sender's configured version.

Prefer `line_sender_buffer_new_for_sender(sender)` when you already have
a sender object — it inherits the right version automatically.
"""
function line_sender_buffer_new(version)
    ccall((:line_sender_buffer_new, libquestdb_client), Ptr{line_sender_buffer}, (Cint,), version)
end


"""
    line_sender_buffer_with_max_name_len(max_name_len)

Create a buffer for serializing ILP messages.
"""
function line_sender_buffer_with_max_name_len(max_name_len)
    ccall((:line_sender_buffer_with_max_name_len, libquestdb_client), Ptr{line_sender_buffer}, (Csize_t,), max_name_len)
end

"""
    line_sender_buffer_free(buffer)

Release the buffer object.
"""
function line_sender_buffer_free(buffer)
    ccall((:line_sender_buffer_free, libquestdb_client), Cvoid, (Ptr{line_sender_buffer},), buffer)
end

"""
    line_sender_buffer_clone(buffer)

Create a new copy of the buffer.
"""
function line_sender_buffer_clone(buffer)
    ccall((:line_sender_buffer_clone, libquestdb_client), Ptr{line_sender_buffer}, (Ptr{line_sender_buffer},), buffer)
end

"""
    line_sender_buffer_reserve(buffer, additional)

Pre-allocate to ensure the buffer has enough capacity for at least the specified additional byte count. This may be rounded up. This does not allocate if such additional capacity is already satisfied. See: `capacity`.
"""
function line_sender_buffer_reserve(buffer, additional)
    ccall((:line_sender_buffer_reserve, libquestdb_client), Cvoid, (Ptr{line_sender_buffer}, Csize_t), buffer, additional)
end

"""
    line_sender_buffer_capacity(buffer)

Get the current capacity of the buffer.
"""
function line_sender_buffer_capacity(buffer)
    ccall((:line_sender_buffer_capacity, libquestdb_client), Csize_t, (Ptr{line_sender_buffer},), buffer)
end

"""
    line_sender_buffer_set_marker(buffer, err_out)

Mark a rewind point. This allows undoing accumulated changes to the buffer for one or more rows by calling `rewind_to_marker`. Any previous marker will be discarded. Once the marker is no longer needed, call `clear_marker`.
"""
function line_sender_buffer_set_marker(buffer, err_out)
    ccall((:line_sender_buffer_set_marker, libquestdb_client), Bool, (Ptr{line_sender_buffer}, Ptr{Ptr{line_sender_error}}), buffer, err_out)
end

"""
    line_sender_buffer_rewind_to_marker(buffer, err_out)

Undo all changes since the last `set_marker` call. As a side-effect, this also clears the marker.
"""
function line_sender_buffer_rewind_to_marker(buffer, err_out)
    ccall((:line_sender_buffer_rewind_to_marker, libquestdb_client), Bool, (Ptr{line_sender_buffer}, Ptr{Ptr{line_sender_error}}), buffer, err_out)
end

"""
    line_sender_buffer_clear_marker(buffer)

Discard the marker.
"""
function line_sender_buffer_clear_marker(buffer)
    ccall((:line_sender_buffer_clear_marker, libquestdb_client), Cvoid, (Ptr{line_sender_buffer},), buffer)
end

"""
    line_sender_buffer_clear(buffer)

Remove all accumulated data and prepare the buffer for new lines. This does not affect the buffer's capacity.
"""
function line_sender_buffer_clear(buffer)
    ccall((:line_sender_buffer_clear, libquestdb_client), Cvoid, (Ptr{line_sender_buffer},), buffer)
end

"""
    line_sender_buffer_size(buffer)

Number of bytes in the accumulated buffer.
"""
function line_sender_buffer_size(buffer)
    ccall((:line_sender_buffer_size, libquestdb_client), Csize_t, (Ptr{line_sender_buffer},), buffer)
end

"""
    line_sender_buffer_peek(buffer, len_out)

Peek into the accumulated buffer that is to be sent out at the next `flush`.

### Parameters
* `buffer`:\\[in\\] Line buffer object.
* `len_out`:\\[out\\] The length in bytes of the accumulated buffer.
### Returns
UTF-8 encoded buffer. The buffer is not nul-terminated.
"""
function line_sender_buffer_peek(buffer, len_out)
    ccall((:line_sender_buffer_peek, libquestdb_client), Ptr{Cchar}, (Ptr{line_sender_buffer}, Ptr{Csize_t}), buffer, len_out)
end

"""
    line_sender_buffer_table(buffer, name, err_out)

Start batching the next row of input for the named table.

### Parameters
* `buffer`:\\[in\\] Line buffer object.
* `name`:\\[in\\] Table name.
"""
function line_sender_buffer_table(buffer, name, err_out)
    ccall((:line_sender_buffer_table, libquestdb_client), Bool, (Ptr{line_sender_buffer}, line_sender_table_name, Ptr{Ptr{line_sender_error}}), buffer, name, err_out)
end

"""
    line_sender_buffer_symbol(buffer, name, value, err_out)

Append a value for a SYMBOL column. Symbol columns must always be written before other columns for any given row.

### Parameters
* `buffer`:\\[in\\] Line buffer object.
* `name`:\\[in\\] Column name.
* `value`:\\[in\\] Column value.
* `err_out`:\\[out\\] Set on error.
### Returns
true on success, false on error.
"""
function line_sender_buffer_symbol(buffer, name, value, err_out)
    ccall((:line_sender_buffer_symbol, libquestdb_client), Bool, (Ptr{line_sender_buffer}, line_sender_column_name, line_sender_utf8, Ptr{Ptr{line_sender_error}}), buffer, name, value, err_out)
end

"""
    line_sender_buffer_column_bool(buffer, name, value, err_out)

Append a value for a BOOLEAN column.

### Parameters
* `buffer`:\\[in\\] Line buffer object.
* `name`:\\[in\\] Column name.
* `value`:\\[in\\] Column value.
* `err_out`:\\[out\\] Set on error.
### Returns
true on success, false on error.
"""
function line_sender_buffer_column_bool(buffer, name, value, err_out)
    ccall((:line_sender_buffer_column_bool, libquestdb_client), Bool, (Ptr{line_sender_buffer}, line_sender_column_name, Bool, Ptr{Ptr{line_sender_error}}), buffer, name, value, err_out)
end

"""
    line_sender_buffer_column_i64(buffer, name, value, err_out)

Append a value for a LONG column.

### Parameters
* `buffer`:\\[in\\] Line buffer object.
* `name`:\\[in\\] Column name.
* `value`:\\[in\\] Column value.
* `err_out`:\\[out\\] Set on error.
### Returns
true on success, false on error.
"""
function line_sender_buffer_column_i64(buffer, name, value, err_out)
    ccall((:line_sender_buffer_column_i64, libquestdb_client), Bool, (Ptr{line_sender_buffer}, line_sender_column_name, Int64, Ptr{Ptr{line_sender_error}}), buffer, name, value, err_out)
end

"""
    line_sender_buffer_column_f64(buffer, name, value, err_out)

Append a value for a DOUBLE column.

### Parameters
* `buffer`:\\[in\\] Line buffer object.
* `name`:\\[in\\] Column name.
* `value`:\\[in\\] Column value.
* `err_out`:\\[out\\] Set on error.
### Returns
true on success, false on error.
"""
function line_sender_buffer_column_f64(buffer, name, value, err_out)
    ccall((:line_sender_buffer_column_f64, libquestdb_client), Bool, (Ptr{line_sender_buffer}, line_sender_column_name, Cdouble, Ptr{Ptr{line_sender_error}}), buffer, name, value, err_out)
end

"""
    line_sender_buffer_column_str(buffer, name, value, err_out)

Append a value for a STRING column.

### Parameters
* `buffer`:\\[in\\] Line buffer object.
* `name`:\\[in\\] Column name.
* `value`:\\[in\\] Column value.
* `err_out`:\\[out\\] Set on error.
### Returns
true on success, false on error.
"""
function line_sender_buffer_column_str(buffer, name, value, err_out)
    ccall((:line_sender_buffer_column_str, libquestdb_client), Bool, (Ptr{line_sender_buffer}, line_sender_column_name, line_sender_utf8, Ptr{Ptr{line_sender_error}}), buffer, name, value, err_out)
end

"""
    line_sender_buffer_column_ts_micros(buffer, name, micros, err_out)

Append a microsecond-precision TIMESTAMP column value.

c-questdb-client 6.0.0 split the old `line_sender_buffer_column_ts` into
`_micros` and `_nanos` variants; this binding keeps the existing high-level
API (which already passes microseconds) and just retargets the symbol.

### Parameters
* `buffer`:\\[in\\] Line buffer object.
* `name`:\\[in\\] Column name.
* `micros`:\\[in\\] The timestamp in microseconds since the unix epoch.
* `err_out`:\\[out\\] Set on error.
### Returns
true on success, false on error.
"""
function line_sender_buffer_column_ts_micros(buffer, name, micros, err_out)
    ccall((:line_sender_buffer_column_ts_micros, libquestdb_client), Bool, (Ptr{line_sender_buffer}, line_sender_column_name, Int64, Ptr{Ptr{line_sender_error}}), buffer, name, micros, err_out)
end

"""
    line_sender_buffer_at_nanos(buffer, epoch_nanos, err_out)

Complete the row with a specified nanosecond timestamp.

Renamed from `line_sender_buffer_at` in c-questdb-client 6.0.0 (the old
name now has `_nanos` / `_micros` variants).

### Parameters
* `buffer`:\\[in\\] Line buffer object.
* `epoch_nanos`:\\[in\\] Number of nanoseconds since 1st Jan 1970 UTC.
* `err_out`:\\[out\\] Set on error.
### Returns
true on success, false on error.
"""
function line_sender_buffer_at_nanos(buffer, epoch_nanos, err_out)
    ccall((:line_sender_buffer_at_nanos, libquestdb_client), Bool, (Ptr{line_sender_buffer}, Int64, Ptr{Ptr{line_sender_error}}), buffer, epoch_nanos, err_out)
end

"""
    line_sender_buffer_at_now(buffer, err_out)

Complete the row without providing a timestamp. The QuestDB instance will insert its own timestamp.

After this call, you can start batching the next row by calling `table` again, or you can send the accumulated batch by calling `flush`.

### Parameters
* `buffer`:\\[in\\] Line buffer object.
* `err_out`:\\[out\\] Set on error.
### Returns
true on success, false on error.
"""
function line_sender_buffer_at_now(buffer, err_out)
    ccall((:line_sender_buffer_at_now, libquestdb_client), Bool, (Ptr{line_sender_buffer}, Ptr{Ptr{line_sender_error}}), buffer, err_out)    
end

mutable struct line_sender end

mutable struct line_sender_opts end

# c-questdb-client 6.0.0 transport protocols.
# Values match the enum order in include/questdb/ingress/line_sender.h.
const LINE_SENDER_PROTOCOL_TCP   = Cint(0)
const LINE_SENDER_PROTOCOL_TCPS  = Cint(1)
const LINE_SENDER_PROTOCOL_HTTP  = Cint(2)
const LINE_SENDER_PROTOCOL_HTTPS = Cint(3)

# c-questdb-client 6.0.0 ILP wire-protocol versions.
# TCP transports do NOT negotiate; default v1 (QuestDB <9 compatible).
const LINE_SENDER_PROTOCOL_VERSION_1 = Cint(1)
const LINE_SENDER_PROTOCOL_VERSION_2 = Cint(2)

"""
    line_sender_opts_new(protocol, host, port)

A new set of options for a line sender connection.

c-questdb-client 6.0.0 added the `protocol` enum as a required first
argument (tcp/tcps/http/https); the old `(host, port)` two-arg form no
longer exists in the .so.

### Parameters
* `protocol`:\\[in\\] One of LINE_SENDER_PROTOCOL_TCP/TCPS/HTTP/HTTPS.
* `host`:\\[in\\] The QuestDB database host.
* `port`:\\[in\\] The QuestDB database port.
"""
function line_sender_opts_new(protocol, host, port)
    ccall((:line_sender_opts_new, libquestdb_client), Ptr{line_sender_opts}, (Cint, line_sender_utf8, UInt16), protocol, host, port)
end

"""
    line_sender_opts_new_service(protocol, host, port)

Same as `line_sender_opts_new` but with the port specified as a service
name (utf8). Also gained the `protocol` first arg in 6.0.0.
"""
function line_sender_opts_new_service(protocol, host, port)
    ccall((:line_sender_opts_new_service, libquestdb_client), Ptr{line_sender_opts}, (Cint, line_sender_utf8, line_sender_utf8), protocol, host, port)
end

# Removed in c-questdb-client 6.0.0 migration:
#   line_sender_opts_net_interface  -> renamed to line_sender_opts_bind_interface
#                                     (also: now returns Bool + err_out param).
# We do not bind the new form because no caller in this fork uses it.

"""
    line_sender_opts_username(opts, username, err_out) -> Bool

Set the username (TCP: ECDSA `kid`; HTTP: basic-auth username).

In c-questdb-client 6.0.0 the old `line_sender_opts_auth` 4-tuple call was
split into four setters with err-out params. Caller must check the Bool
and bail on false.
"""
function line_sender_opts_username(opts, username, err_out)
    ccall((:line_sender_opts_username, libquestdb_client), Bool, (Ptr{line_sender_opts}, line_sender_utf8, Ptr{Ptr{line_sender_error}}), opts, username, err_out)
end

"""
    line_sender_opts_token(opts, token, err_out) -> Bool

TCP: ECDSA private key `d`. HTTP: bearer token.
"""
function line_sender_opts_token(opts, token, err_out)
    ccall((:line_sender_opts_token, libquestdb_client), Bool, (Ptr{line_sender_opts}, line_sender_utf8, Ptr{Ptr{line_sender_error}}), opts, token, err_out)
end

"""
    line_sender_opts_token_x(opts, token_x, err_out) -> Bool

ECDSA public key X coordinate (TCP auth only).
"""
function line_sender_opts_token_x(opts, token_x, err_out)
    ccall((:line_sender_opts_token_x, libquestdb_client), Bool, (Ptr{line_sender_opts}, line_sender_utf8, Ptr{Ptr{line_sender_error}}), opts, token_x, err_out)
end

"""
    line_sender_opts_token_y(opts, token_y, err_out) -> Bool

ECDSA public key Y coordinate (TCP auth only).
"""
function line_sender_opts_token_y(opts, token_y, err_out)
    ccall((:line_sender_opts_token_y, libquestdb_client), Bool, (Ptr{line_sender_opts}, line_sender_utf8, Ptr{Ptr{line_sender_error}}), opts, token_y, err_out)
end

"""
    line_sender_opts_protocol_version(opts, version, err_out) -> Bool

Pin the ILP wire-protocol version. TCP does NOT negotiate, so callers
SHOULD explicitly set v1 (QuestDB <9 compatible) or v2 (QuestDB ≥9, supports
arrays). Pass one of LINE_SENDER_PROTOCOL_VERSION_1 / _VERSION_2.
"""
function line_sender_opts_protocol_version(opts, version, err_out)
    ccall((:line_sender_opts_protocol_version, libquestdb_client), Bool, (Ptr{line_sender_opts}, Cint, Ptr{Ptr{line_sender_error}}), opts, version, err_out)
end

# Removed in c-questdb-client 6.0.0 migration:
#   line_sender_opts_tls_ca         -> symbol still exists but takes a
#                                     `line_sender_ca` enum, NOT a utf8 path.
#                                     Old binding would silently corrupt opts.
#   line_sender_opts_tls_insecure_skip_verify -> replaced by
#                                     line_sender_opts_tls_verify(opts, false, &err).
#   line_sender_opts_read_timeout   -> renamed to line_sender_opts_auth_timeout
#                                     (now Bool + err_out param).
# No caller in this fork uses these; bind on demand if a use case appears.

"""
    line_sender_opts_clone(opts)

Duplicate the opts object. Both old and new objects will have to be freed.
"""
function line_sender_opts_clone(opts)
    ccall((:line_sender_opts_clone, libquestdb_client), Ptr{line_sender_opts}, (Ptr{line_sender_opts},), opts)
end

"""
    line_sender_opts_free(opts)

Release the opts object.
"""
function line_sender_opts_free(opts)
    ccall((:line_sender_opts_free, libquestdb_client), Cvoid, (Ptr{line_sender_opts},), opts)
end

"""
    line_sender_build(opts, err_out)

Build a sender from the opts (renamed from `line_sender_connect` in
c-questdb-client 6.0.0). Returns NULL on error; `err_out` carries detail.

!!! note

    The opts object is consumed by the call. Do not call `opts_free` on it.

### Parameters
* `opts`:\\[in\\] Options for the connection.
"""
function line_sender_build(opts, err_out)
    ccall((:line_sender_build, libquestdb_client), Ptr{line_sender}, (Ptr{line_sender_opts}, Ptr{Ptr{line_sender_error}}), opts, err_out)
end



"""
    line_sender_flush(sender, buffer, err_out)

Send buffer of rows to the QuestDB server.

The buffer will be automatically cleared, ready for re-use. If instead you want to preserve the buffer contents, call `flush_and_keep`.

### Parameters
* `sender`:\\[in\\] Line sender object.
* `buffer`:\\[in\\] Line buffer object.
### Returns
true on success, false on error.
"""
function line_sender_flush(sender, buffer, err_out)
    ccall((:line_sender_flush, libquestdb_client), Bool, (Ptr{line_sender}, Ptr{line_sender_buffer}, Ptr{Ptr{line_sender_error}}), sender, buffer, err_out)
end

"""
    line_sender_flush_and_keep(sender, buffer, err_out)

Send buffer of rows to the QuestDB server.

The buffer will left untouched and must be cleared before re-use. To send and clear in one single step, `flush` instead.

### Parameters
* `sender`:\\[in\\] Line sender object.
* `buffer`:\\[in\\] Line buffer object.
### Returns
true on success, false on error.
"""
function line_sender_flush_and_keep(sender, buffer, err_out)
    ccall((:line_sender_flush_and_keep, libquestdb_client), Bool, (Ptr{line_sender}, Ptr{line_sender_buffer}, Ptr{Ptr{line_sender_error}}), sender, buffer, err_out)
end

"""
    line_sender_must_close(sender)

Check if an error occurred previously and the sender must be closed.

### Parameters
* `sender`:\\[in\\] Line sender object.
### Returns
true if an error occurred with a sender and it must be closed.
"""
function line_sender_must_close(sender)
    ccall((:line_sender_must_close, libquestdb_client), Bool, (Ptr{line_sender},), sender)
end

"""
    line_sender_close(sender)

Close the connection. Does not flush. Non-idempotent.

### Parameters
* `sender`:\\[in\\] Line sender object.
"""
function line_sender_close(sender)
    ccall((:line_sender_close, libquestdb_client), Cvoid, (Ptr{line_sender},), sender)
end

export
    # Types / structs
    line_sender, line_sender_opts, line_sender_buffer, line_sender_error, line_sender_error_code,
    line_sender_utf8, line_sender_utf8_assert,
    line_sender_table_name, line_sender_table_name_assert,
    line_sender_column_name, line_sender_column_name_assert,
    # 6.0.0 protocol + protocol-version enum constants
    LINE_SENDER_PROTOCOL_TCP, LINE_SENDER_PROTOCOL_TCPS,
    LINE_SENDER_PROTOCOL_HTTP, LINE_SENDER_PROTOCOL_HTTPS,
    LINE_SENDER_PROTOCOL_VERSION_1, LINE_SENDER_PROTOCOL_VERSION_2,
    # utf8 / name init
    line_sender_utf8_init, line_sender_table_name_init, line_sender_column_name_init,
    # error
    line_sender_error_get_code, line_sender_error_msg, line_sender_error_free,
    # buffer lifecycle
    line_sender_buffer_new, line_sender_buffer_with_max_name_len,
    line_sender_buffer_free, line_sender_buffer_clone,
    line_sender_buffer_reserve, line_sender_buffer_capacity,
    line_sender_buffer_set_marker, line_sender_buffer_rewind_to_marker, line_sender_buffer_clear_marker,
    line_sender_buffer_clear, line_sender_buffer_size, line_sender_buffer_peek,
    # buffer row-building
    line_sender_buffer_table, line_sender_buffer_symbol,
    line_sender_buffer_column_bool, line_sender_buffer_column_i64,
    line_sender_buffer_column_f64, line_sender_buffer_column_str,
    line_sender_buffer_column_ts_micros, line_sender_buffer_at_nanos, line_sender_buffer_at_now,
    # opts (6.0.0)
    line_sender_opts_new, line_sender_opts_new_service,
    line_sender_opts_username, line_sender_opts_token,
    line_sender_opts_token_x, line_sender_opts_token_y,
    line_sender_opts_protocol_version,
    line_sender_opts_clone, line_sender_opts_free,
    # sender lifecycle
    line_sender_build, line_sender_flush, line_sender_flush_and_keep,
    line_sender_must_close, line_sender_close

end # module



