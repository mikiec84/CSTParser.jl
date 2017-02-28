parse_kw(ps::ParseState, ::Type{Val{Tokens.IMPORT}}) = parse_imports(ps)
parse_kw(ps::ParseState, ::Type{Val{Tokens.IMPORTALL}}) = parse_imports(ps)
parse_kw(ps::ParseState, ::Type{Val{Tokens.USING}}) = parse_imports(ps)
parse_kw(ps::ParseState, ::Type{Val{Tokens.EXPORT}}) = parse_export(ps)

function parse_kw(ps::ParseState, ::Type{Val{Tokens.MODULE}})
    start = ps.t.startbyte
    kw = INSTANCE(ps)
    arg = @closer ps block @closer ps ws parse_expression(ps)
    scope = Scope{Tokens.MODULE}(get_id(arg), [])
    block = @scope ps scope parse_block(ps)
    next(ps)
    push!(ps.current_scope.args, scope)
    return EXPR(kw, [TRUE, arg, block], ps.nt.startbyte - start, [INSTANCE(ps)], scope)
end

function parse_kw(ps::ParseState, ::Type{Val{Tokens.BAREMODULE}})
    start = ps.t.startbyte
    kw = INSTANCE(ps)
    arg = @closer ps block @closer ps ws parse_expression(ps)
    scope = Scope{Tokens.MODULE}(get_id(arg), [])
    block = @scope ps scope parse_block(ps)
    next(ps)
    push!(ps.current_scope.args, scope)
    return EXPR(kw, [FALSE, arg, block], ps.nt.startbyte - start, [INSTANCE(ps)], scope)
end

function parse_dot_mod(ps::ParseState)
    args = []
    while true
        next(ps)
        if ps.t.kind == Tokens.AT_SIGN
            next(ps)
            a = INSTANCE(ps)
            a.val = Symbol('@', a.val)
            a.span +=1
            a.offset -=1
            push!(args, a)
        else
            push!(args, INSTANCE(ps))
        end
        if ps.nt.kind != Tokens.DOT
            break
        end
        next(ps)
    end
    args
end


function parse_imports(ps::ParseState)
    start = ps.t.startbyte
    kw = INSTANCE(ps)
    tk = ps.t.kind
    dots = []

    while ps.nt.kind==Tokens.DOT || ps.nt.kind==Tokens.DDOT || ps.nt.kind==Tokens.DDDOT
        next(ps)
        d = INSTANCE(ps)
        for i = 1:d.span
            push!(dots, OPERATOR{15,Tokens.DOT,false}(1, ps.nt.startbyte+i))
        end
    end

    arg = vcat(dots, parse_dot_mod(ps))

    if ps.nt.kind!=Tokens.COMMA && ps.nt.kind!=Tokens.COLON
        return EXPR(kw, arg, kw.span + sum(x.span for x in arg) + length(arg)-1)
    end
    ret = EXPR(TOPLEVEL,[], 0, [kw])
    
    if ps.nt.kind == Tokens.COLON
        next(ps)
        push!(ret.punctuation, INSTANCE(ps))
        M = arg
        arg = vcat(M, parse_dot_mod(ps))
        push!(ret.args, EXPR(KEYWORD{tk}(0,0), arg, sum(x.span for x in arg) + length(arg)-1))
        while ps.nt.kind == Tokens.COMMA
            next(ps)
            push!(ret.punctuation, INSTANCE(ps))
            arg = vcat(M, parse_dot_mod(ps))
            push!(ret.args, EXPR(KEYWORD{tk}(0,0), arg, sum(x.span for x in arg) + length(arg)-1))
        end
    else
        push!(ret.args, EXPR(KEYWORD{tk}(0,0), arg, sum(x.span for x in arg) + length(arg)-1))
        while ps.nt.kind == Tokens.COMMA
            next(ps)
            push!(ret.punctuation, INSTANCE(ps))
            arg = parse_dot_mod(ps)
            push!(ret.args, EXPR(KEYWORD{tk}(0,0), arg, sum(x.span for x in arg) + length(arg)-1))
        end
    end
    
    # if length(ret.args) == 1
    #     puncs = ret.punctuation
    #     ret = ret.args[1]
    #     ret.punctuation = puncs
    #     ret.head = kw
    #     ret.span += kw.span
    # end

    # Linting
    if ps.current_scope isa Scope{Tokens.FUNCTION}
        push!(ps.hints, Hint{Hints.ImportInFunction}(kw.offset + (1:ret.span)))
    end

    ret.span = ps.nt.startbyte - start
    return ret
end

function parse_export(ps::ParseState)
    start = ps.t.startbyte
    kw = INSTANCE(ps)
    
    ret = EXPR(kw, [parse_dot_mod(ps)[1]], 0, [])
    
    while ps.nt.kind == Tokens.COMMA
        next(ps)
        push!(ret.punctuation, INSTANCE(ps))
        arg = parse_dot_mod(ps)[1]
        push!(ret.args, arg)
    end
    
    if ps.current_scope isa Scope{Tokens.FUNCTION}
        push!(ps.hints, Hint{Hints.ImportInFunction}(kw.offset + (1:ret.span)))
    end
    ret.span = ps.nt.startbyte - start
    return ret
end

function _start_imports(x::EXPR)
    return Iterator{:imports}(1, length(x.args) * 2) 
end

function next(x::EXPR, s::Iterator{:imports})
    if s.i == 1
        return x.head, +s
    elseif isodd(s.i)
        return PUNCTUATION{Tokens.DOT}(1,0), +s
    else
        return x.args[div(s.i, 2)], +s
    end
end

function next(x::EXPR, s::Iterator{:export})
    if s.i == 1
        return x.head, +s
    elseif isodd(s.i)
        return x.punctuation[div(s.i-1, 2)], +s
    else
        return x.args[div(s.i, 2)], +s
    end
end


function next(x::EXPR, s::Iterator{:module})
    if s.i == 1
        return x.head, +s
    elseif s.i == 2
        return x.args[2], +s
    elseif s.i == 3
        return x.args[3], +s
    elseif s.i == 4
        return x.punctuation[1], +s
    end
end

function next(x::EXPR, s::Iterator{:toplevel})
    if s.i == 1
        return x.args[1].head, +s
    elseif isodd(s.i)
        return x.punctuation[div(s.i-1, 2)], +s
    else
        if s.i <= div(s.n, 2)
            return x.args[1].args[div(s.i, 2)], +s
        else
            # this needs to be fixed for `import A: a, b.c`
            return last(x.args[div(s.i-div(s.n, 2)+1, 2)].args), +s
        end
    end
end
