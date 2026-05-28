
module QuestDB

include("LibQuestDB.jl")

using .LibQuestDB 
using Dates

struct Table{T}
    sender::T
end

struct Column{T}
    sender::T
end

struct Symbol{T}
    sender::T
end

struct At{T}
    sender::T
end

struct AtNow{T}
    sender::T
end

struct Flush{T}
    sender::T
end

struct Close{T}
    sender::T
end

"""
    Sender(host, port; protocol=:tcps, tls=nothing, auth=nothing, init_capacity=64*1024)

Open a QuestDB ILP sender against `host`:`port` using c-questdb-client 6.x.

## Parameters

* `host`, `port`: target QuestDB ILP endpoint.
* `protocol`: one of `:tcp`, `:tcps`, `:http`, `:https`. Defaults to `:tcps`
  (TLS + ILP TCP, the production posture for IENAI).
* `tls`: legacy boolean kwarg. If passed and `protocol` is left at default,
  `true` is interpreted as `:tcps` and `false` as `:tcp`. Prefer `protocol`
  in new code.
* `auth`: `(kid, d, x, y)` tuple for ECDSA TCP auth, or `nothing`.
* `init_capacity`: initial ILP buffer reserve in bytes.

## Methods on the returned object

* `table(name)` / `symbol(name, val)` / `column(name, val)` / `at(ns)` /
  `at_now()` / `flush()` / `close()`

## c-questdb-client 6.x migration notes (only relevant for maintainers)

* `line_sender_opts_new` now takes `protocol` as first arg; we map our
  Symbol → enum constant via `_resolve_protocol`.
* TLS is no longer a separate opts toggle; it is implied by `:tcps`/`:https`.
* Auth is no longer a single 4-arg call but 4 setters (`username`, `token`,
  `token_x`, `token_y`), each of which can fail. We propagate failures.
* `line_sender_connect` was renamed to `line_sender_build`.
* TCP transport does not negotiate the wire-protocol version, so we
  explicitly pin v1 (compatible with QuestDB <9, which IENAI's dev/staging
  fleet still runs).
"""
mutable struct Sender
    host_utf8::Ref{line_sender_utf8}
    port::Ref{UInt16}
    key_id_utf8::Ref{line_sender_utf8}
    priv_key_utf8::Ref{line_sender_utf8}
    pub_key_x_utf8::Ref{line_sender_utf8}
    pub_key_y_utf8::Ref{line_sender_utf8}
    buffer::Ptr{line_sender_buffer}
    err::Ref{Ptr{line_sender_error}}
    sender::Ptr{line_sender}
    auth::Bool

    function Sender(host::String="localhost", port::Int=9009;
                    protocol::Base.Symbol=:tcps,
                    tls::Union{Bool,Nothing}=nothing,
                    auth=nothing,
                    init_capacity::Int=64 * 1024)
        # Resolve effective protocol: explicit `protocol` wins; otherwise
        # honour the legacy `tls` boolean. :tcp/:tcps flip per tls.
        effective_protocol = if tls === nothing
            protocol
        elseif protocol == :tcps && tls === false
            :tcp
        elseif protocol == :tcp && tls === true
            :tcps
        else
            protocol
        end
        proto_enum = _resolve_protocol(effective_protocol)

        err = Ref{Ptr{line_sender_error}}(C_NULL)
        port_ref = Ref{UInt16}(port)
        host_utf8 = Ref{line_sender_utf8}()
        key_id_utf8 = Ref{line_sender_utf8}()
        priv_key_utf8 = Ref{line_sender_utf8}()
        pub_key_x_utf8 = Ref{line_sender_utf8}()
        pub_key_y_utf8 = Ref{line_sender_utf8}()

        # Buffer encoder version MUST match the sender's; the server-side
        # flush enforces this. We pin both to v1 for QuestDB <9 compatibility.
        buffer = line_sender_buffer_new(LINE_SENDER_PROTOCOL_VERSION_1)
        line_sender_buffer_reserve(buffer, init_capacity)

        if !line_sender_utf8_init(host_utf8, length(host), host, err)
            _abort_init(buffer, err, "host utf8 init failed")
        end

        opts = line_sender_opts_new(proto_enum, host_utf8[], port_ref[])
        if opts == C_NULL
            _abort_init(buffer, err, "line_sender_opts_new returned NULL")
        end

        # Pin wire-protocol v1 (QuestDB <9 compatible). v2 only matters for
        # array types we do not ingest.
        if !line_sender_opts_protocol_version(opts, LINE_SENDER_PROTOCOL_VERSION_1, err)
            line_sender_opts_free(opts)
            _abort_init(buffer, err, "protocol_version v1 setup failed")
        end

        if auth !== nothing
            length(auth) == 4 || (line_sender_opts_free(opts); error("auth must be a 4-tuple (kid, d, x, y)"))
            kid, d, x, y = auth

            line_sender_utf8_init(key_id_utf8,   length(kid), kid, err) ||
                (line_sender_opts_free(opts); _abort_init(buffer, err, "kid utf8 init failed"))
            line_sender_utf8_init(priv_key_utf8, length(d),   d,   err) ||
                (line_sender_opts_free(opts); _abort_init(buffer, err, "d utf8 init failed"))
            line_sender_utf8_init(pub_key_x_utf8, length(x),  x,   err) ||
                (line_sender_opts_free(opts); _abort_init(buffer, err, "x utf8 init failed"))
            line_sender_utf8_init(pub_key_y_utf8, length(y),  y,   err) ||
                (line_sender_opts_free(opts); _abort_init(buffer, err, "y utf8 init failed"))

            line_sender_opts_username(opts, key_id_utf8[],   err) ||
                (line_sender_opts_free(opts); _abort_init(buffer, err, "opts_username failed"))
            line_sender_opts_token(opts,    priv_key_utf8[], err) ||
                (line_sender_opts_free(opts); _abort_init(buffer, err, "opts_token failed"))
            line_sender_opts_token_x(opts,  pub_key_x_utf8[], err) ||
                (line_sender_opts_free(opts); _abort_init(buffer, err, "opts_token_x failed"))
            line_sender_opts_token_y(opts,  pub_key_y_utf8[], err) ||
                (line_sender_opts_free(opts); _abort_init(buffer, err, "opts_token_y failed"))
        end

        # `line_sender_build` consumes opts (success or failure) — do NOT
        # call line_sender_opts_free on the returned opts pointer afterwards.
        sender_ptr = line_sender_build(opts, err)
        if sender_ptr == C_NULL
            _abort_init(buffer, err, "line_sender_build returned NULL")
        end

        return new(host_utf8, port_ref, key_id_utf8, priv_key_utf8,
                   pub_key_x_utf8, pub_key_y_utf8,
                   buffer, err, sender_ptr, auth !== nothing)
    end
end

# Symbol -> c-questdb-client protocol enum.
function _resolve_protocol(p::Base.Symbol)
    p === :tcp   && return LINE_SENDER_PROTOCOL_TCP
    p === :tcps  && return LINE_SENDER_PROTOCOL_TCPS
    p === :http  && return LINE_SENDER_PROTOCOL_HTTP
    p === :https && return LINE_SENDER_PROTOCOL_HTTPS
    error("Unknown QuestDB protocol $(p); use one of :tcp, :tcps, :http, :https")
end

# Abort path during Sender construction: surface the C error message,
# release the dangling buffer, and throw.
function _abort_init(buffer, err::Ref{Ptr{line_sender_error}}, context::String)
    if err[] != C_NULL
        len = Ref{Csize_t}(0)
        msg_ptr = line_sender_error_msg(err[], len)
        msg = unsafe_string(msg_ptr, len[])
        line_sender_error_free(err[])
        if buffer != C_NULL
            line_sender_buffer_free(buffer)
        end
        throw(ErrorException("QuestDB Sender init failed [$context]: $msg"))
    else
        if buffer != C_NULL
            line_sender_buffer_free(buffer)
        end
        throw(ErrorException("QuestDB Sender init failed [$context]: no error detail available"))
    end
end

function Base.getproperty(s::Sender, f::Base.Symbol)    
    if f == :table        
        return Table(s)    
    elseif f == :column
        return Column(s)
    elseif f == :symbol
        return Symbol(s)
    elseif f == :at
        return At(s)
    elseif f == :at_now
        return AtNow(s)
    elseif f == :flush
        return Flush(s)
    elseif f == :close
        return Close(s)
    end

    return getfield(s, f)
end

function error_handler(sender::Ptr{line_sender}, buffer::Ptr{line_sender_buffer}, err::Ref{Ptr{line_sender_error}})
    code = line_sender_error_get_code(err[])
    len = Ref{Csize_t}(100)
    message = line_sender_error_msg(err[], len)
    msg_str = unsafe_string(message, len[])
    println(msg_str)

    label = if code == 0
        "Could not resolve address"
    elseif code == 1
        "Invalid API call"
    elseif code == 2
        "Socket error"
    elseif code == 3
        "Invalid UTF8"
    elseif code == 4
        "Invalid name"
    elseif code == 5
        "Invalid timestamp"
    elseif code == 6
        "Auth error"
    elseif code == 7
        "TLS error"
    else
        "Unknown error (code=$code)"
    end

    line_sender_error_free(err[])
    if buffer != C_NULL
        line_sender_buffer_free(buffer)
    end
    if sender != C_NULL
        line_sender_close(sender)
    end
    throw(ErrorException("$label, Message: $msg_str"))
end

function capacity(sender::Sender)
    return line_sender_buffer_capacity(sender.buffer)    
end


"""
    Creates a table with the given `name` in the database. The table will be created with the
    given `columns` and `types`. The `columns` and `types` must be of the same length.

    ## Parameters
    * `name`: Name of the table to create.
    * `columns`: Names of the columns in the table.
    * `types`: Types of the columns in the table.

    ## Example
    ```julia
    sender = Sender("localhost", "9000")
    sender.table("my_table", ["col1", "col2"], ["int", "string"])
    ```
"""
function(table::Table)(name::String)
    sender = table.sender
    table_name = line_sender_table_name_assert(length(name), name);                                         
    line_sender_buffer_table(sender.buffer, table_name, sender.err);                        
    
    if (sender.err[] != C_NULL)
        error_handler(sender.sender, sender.buffer, sender.err);           
    end

    sender
end

"""
    Creates a symbol with the given `name` and `column_value` in the database. The symbol will be created with the
    given `columns` and `types`. The `columns` and `types` must be of the same length.

    ## Parameters
    * `name`: Name of the symbol to create.
    * `column_value`: Value of the column in the symbol.

    ## Example
    ```julia
    sender = Sender("localhost", "9000")
    sender.symbol("my_symbol", "my_column_value")
    ```

    ## Notes
    * The `column_value` must be a string. 
"""
function(symbol::Symbol)(name::String, column_value::String)    
    sender = symbol.sender
    col_name = line_sender_column_name_assert(length(name), name);
    column_pointer = Ref{line_sender_utf8}();
    
    line_sender_utf8_init(column_pointer, length(column_value), column_value, sender.err);                           
    line_sender_buffer_symbol(sender.buffer, col_name, column_pointer[], sender.err);

    if (sender.err[] != C_NULL)
        return error_handler(sender.sender, sender.buffer, sender.err);           
    end    
    sender
end


"""
    Creates a column with the given `name` and `column_value` in the database. The column will be created with the
    given `columns` and `types`. The `columns` and `types` must be of the same length.

    ## Parameters
    * `name`: Name of the column to create.
    * `column_value`: Value of the column.

    ## Example
    ```julia
    sender = Sender("localhost", "9000")
    sender.column("my_column", 1)
    ```

    ## Notes
    * The `column_value` must be a string, int64, float64, bool or a date. 
"""
function(column::Column)(name::String, column_value::Union{String, Int64, Float64, Bool, Dates.Microsecond})
    sender = column.sender
    col_name = line_sender_column_name_assert(length(name), name);
    column_pointer = Ref{line_sender_utf8}();        

    if column_value isa String
        line_sender_utf8_init(column_pointer, length(column_value), column_value, sender.err);                           
        line_sender_buffer_column_str(sender.buffer, col_name, column_pointer[], sender.err);
    elseif column_value isa Int64
        line_sender_buffer_column_i64(sender.buffer, col_name, column_value, sender.err);                                        
    elseif column_value isa Float64
        line_sender_buffer_column_f64(sender.buffer, col_name, column_value, sender.err);                                        
    elseif column_value isa Bool
        line_sender_buffer_column_bool(sender.buffer, col_name, column_value, sender.err);                                                
    elseif column_value isa Microsecond
        ts = convert(Int64, Dates.value(column_value));
        line_sender_buffer_column_ts_micros(sender.buffer, col_name, ts, sender.err);
    else
        throw("Unsupported type: $(typeof(column_value))");        
    end;

    if (sender.err[] != C_NULL)
        return error_handler(sender.sender, sender.buffer, sender.err);
    end        
    sender
end

"""at
    Adds a column with the given `ts` timestamp to the buffer of the sender object.
        
    Parameters
    ----------
    ts: Dates.Nanosecond
        Timestamp to add to the buffer.

    Returns
    -------
    None

    ## Example
    ```julia
    sender = Sender("localhost", "9000")
    sender.table("my_table", ["col1", "col2"], ["int", "string"])
    sender.column("col1", 1)
    sender.column("col2", "hello")
    ts = Dates.Microsecond(1620000000000)
    sender.at(ts)
    sender.flush()
    ```
"""
function(at::At)(ts::Dates.Nanosecond)
    sender = at.sender
    ts_ns = convert(Int64, Dates.value(ts))
    line_sender_buffer_at_nanos(sender.buffer, ts_ns, sender.err)

    if (sender.err[] != C_NULL)
        return error_handler(sender.sender, sender.buffer, sender.err)
    end
    sender
end

"""Sender.at_now
    Adds a column with the current timestamp to the buffer of the sender object.
    
    Returns
    -------
    None

    ## Example
    ```julia
    sender = Sender("localhost", "9000")
    sender.table("my_table")
    sender.column("col1", 1)
    sender.column("col2", "hello")
    sender.at_now()
    sender.flush()
    ```
"""
function(at_now::AtNow)()    
    sender = at_now.sender
    line_sender_buffer_at_now(sender.buffer, sender.err);       

    if (sender.err[] != C_NULL)
        return error_handler(sender.sender, sender.buffer, sender.err);           
    end
    sender
end

"""
    Flush the buffer of the sender object to the database.    

    Notes
    -----
    * The buffer is flushed automatically when the buffer is full.
    * The buffer is flushed automatically when the `Sender` object is garbage collected.
    * The buffer is flushed automatically when the `Sender` object is closed.
"""
function(flush::Flush)()
    println("Flushing...");
    sender = flush.sender
    line_sender_flush(sender.sender, sender.buffer, sender.err);    
    if sender.err[] != C_NULL          
        return error_handler(sender.sender, sender.buffer, sender.err);           
    end;    
end

"""
    Close the sender object.    
            
"""
function(close::Close)()
    println("Closing...");
    sender = close.sender
    line_sender_close(sender.sender);
end

export Sender, capacity

end