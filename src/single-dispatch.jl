module SingleDispatch

using Memoize
using MacroTools

export @base, @extend, @virtual, @overload, @polymorphic

# TODO: Change to this
"""
    @interface BaseClass begin
        @virtual function func1(this, arg1::Int)::ReturnType end
        @virtual function func2(this)::ReturnType end
    end
"""
macro interface(interface_name, body::Expr)
    return quote
        #abstract type
        $(esc(type_def))
    end
end


"""
    @base abstract type BaseClass end
    @virtual BaseClass function func1(this, arg1::Int)::ReturnType end
    @virtual BaseClass function func2(this)::ReturnType end
"""
macro base(type_def::Expr)
    @assert type_def.head == :abstract
    return quote
        $(esc(type_def))
    end
end
"""
    @virtual BaseClass function func_name(this::Ptr, args...)::ReturnType end
"""
macro virtual(base::Any, func::Expr)
    if !(base isa Type)
        base = Core.eval(__module__, base)
    end
    spec = vtable_spec(base)
    _emit_virtual_func(__module__, base, spec, func)
end

"""
    @extend struct DerivedClass <: BaseClass
        @override function func1(this::Ptr, args...)::ReturnType
            # ...
        end
        @override function func2(this::Ptr, args...)::ReturnType
            # ...
        end
    end
"""
macro extend(struct_def::Expr)
    @assert struct_def.head == :struct
    body = struct_def.args[3].args
    new_body = Any[]
    @assert struct_def.args[2] isa Expr && struct_def.args[2].head === :(<:)  "@extend must be used with a <: expression."
    base_type = Core.eval(__module__, struct_def.args[2].args[2])
    spec = vtable_spec(base_type)
    if spec.default_impls !== nothing
        vtable = copy(spec.default_impls)
    else
        vtable = VTable(length(spec.functions))
    end
    type = struct_def.args[2].args[1]
    functions = []
    for expr in body
        #@show expr
        #dump(expr)
        if expr isa Expr && expr.head === :macrocall && expr.args[1] === Symbol("@override")
            #@info "inside"
            @assert expr.args[3].head === :function
            f = _emit_override_func(__module__, spec, vtable, type, expr.args[3])
            push!(functions, f)
        else
            push!(new_body, expr)
        end
    end
    # Add the vtable into the struct, as the first field.
    pushfirst!(new_body, :(vtable::$VTable))

    struct_def.args[3].args = new_body
    return quote
        $(esc(struct_def))
        $(esc(type))(args...) = $(esc(type))($vtable, args...)
        $(functions...)
    end
end
macro override(func::Expr)
    @assert "`@override function ... end` should be placed inside an `@extend` struct definition."
end

macro polymorphic(call::Expr)
    @assert call.head == :call
    name = call.args[1]
    mutable_name = fname_mutable(name)
    immutable_name = fname_immutable(name)
    this = call.args[2]
    esc(quote
        this = $this
        if ismutable(this)
            $mutable_name(this, $(call.args[3:end]...))
        else
            $immutable_name(this, $(call.args[3:end]...))
        end
    end)
end

fname_mutable(name) = Symbol("@$(name)-mutable")
fname_immutable(name) = Symbol("@$(name)-immutable")

function _args_split(func_expr::Expr)
    args = func_expr.args[1].args[1].args[3:end]
    @assert all(a->(a isa Expr && a.head == :(::)), args)  "All function args (after the first) must have fully specified C types (for now at least)."
    arg_types = [arg.args[2] for arg in args]
    @assert all(a->(a isa Expr && a.head == :(::) && length(a.args) == 2), args)  "All function args (after the first) must have names."
    arg_names = [arg.args[1] for arg in args]
    return args, arg_names, arg_types
end

function _emit_virtual_func(__module__::Module, BaseType, spec, func_expr::Expr)
    name = func_expr.args[1].args[1].args[1]
    name_mutable = fname_mutable(name)
    name_immutable = fname_immutable(name)
    return_type = func_expr.args[1].args[2]
    func = Core.eval(__module__, :(function $name end))
    args, arg_names, arg_types = _args_split(func_expr)
    idx = _declare_virtual_method!(spec, func)
    return quote
        # Force inline to ensure no dispatch to this function
        @inline function $(esc(name_mutable))(obj, args...)::$(esc(return_type))
            p = _unsafe_pointer_from_objref(obj)
            return do_dispatch(p::Ptr{Cvoid}, args...)
        end
        # Force inline to ensure no dispatch to this function
        @inline function $(esc(name_immutable))(obj, args...)::$(esc(return_type))
            # This is the last allocation we're left with.. It's the same as seen in
            # https://github.com/JuliaLang/julia/issues/44244#issuecomment-1236165936
            # It's annoying, because the whole reason someone is using this `@polymorphic`
            # call is because they have a dynamic object reference (i.e. a *pointer*), yet
            # julia won't let us take the address of that object, so we have to _copy_ it
            # into a new heap allocation just to get its address.
            # I guess the best approach would be to use mutable objects for polymorphism if
            # you're going to have them in heap allocated objects anyway.
            #Core.println("before ref")
            r = Ref{Any}(obj)
            ref_ptr = pointer_from_objref(r)
            GC.@preserve r begin
                #Core.println("before dispatch")
                obj_ptr = unsafe_load(reinterpret(Ptr{Ptr{Cvoid}}, ref_ptr))
                return do_dispatch(obj_ptr::Ptr{Cvoid}, args...)
            end
        end
        function do_dispatch(p::Ptr{Cvoid}, $(args...))
            vtable = unsafe_load(reinterpret(Ptr{VTable}, p), 1)
            # TODO: Make this safe
            f_ptr = @inbounds(vtable.func_ptrs[$idx])::Ptr{Cvoid}
            # TODO: arg types
            ccall(f_ptr, $return_type, (Ptr{Cvoid}, $(arg_types...)), p, $(arg_names...))
        end
    end
end
function _unsafe_pointer_from_objref(obj)
    # Copied from base, but remove the redundant `ismutable()` check, since we already
    # checked it before calling.
    ccall(:jl_value_ptr, Ptr{Cvoid}, (Any,), obj)
end

function _emit_override_func(__module__::Module, spec, vtable, type, func_expr::Expr)
    #@assert func_expr.args[1].args[1].args[2].args[2] === :(Ptr{$type})
    fname = gensym(:func)
    @assert func_expr.args[1].head == :(::) "@override Must specify return value"
    args, arg_names, arg_types = _args_split(func_expr)
    return_type = func_expr.args[1].args[2]
    wrapper_name = gensym(:wrapper)
    f_ptr_name = gensym(:f_ptr)
    return esc(quote
        const $fname = $func_expr
        $(if ismutabletype(type)
            quote
                function $wrapper_name(this::Ptr{Cvoid}, $(args...))
                    @info "inside wrapper. Args: $args"
                    o = $unsafe_pointer_to_objref(this)
                    return $fname(o::$type, $(arg_names...))
                end
            end
        else
            quote
                function $wrapper_name(this::Ptr{Cvoid}, $(args...))
                    o = unsafe_load(reinterpret(Ptr{$type}, this))::$type
                    return $fname(o::$type, $(arg_names...))
                end
            end
        end)
        # TODO: arg types
        const $f_ptr_name = @eval @cfunction($wrapper_name, $return_type, (Ptr{Cvoid}, $(arg_types...)))
        $_define_virtual_method!($spec, $vtable, $fname, $f_ptr_name)
    end)
end


# Contains the max number of methods any child of parent has.
#struct _VTableSpec{VTABLE}  # (break the circular dependency)
#    base_type::Type
#    #parent_spec::Union{_VTableSpec{SPEC}, Nothing}  # For chained inheritance. (TODO)
#    functions::Dict{Function, Int}  # Maps function to index in func_ptrs.
#    instantiations::Vector{VTABLE}
#    _VTableSpec{VTABLE}(base_type) where VTABLE = new{VTABLE}(base_type, Dict{Function,Int}(), VTABLE[])
#end
# Has one entry for every function in the VTableSpec.
struct VTable
    #type::Type
    #parent::_VTableSpec{VTable}
    #parent::VTableSpec
    func_ptrs::Vector{Ptr{Cvoid}}
end
VTable(n::Int) = VTable(Ptr{Cvoid}[C_NULL for i in 1:n])
mutable struct VTableSpec
    base_type::Type
    #parent_spec::Union{_VTableSpec{SPEC}, Nothing}  # For chained inheritance. (TODO)
    functions::Vector{Function}  # Maps function to index in func_ptrs.
    default_impls::Union{Nothing,VTable}  # optional default implementations
    VTableSpec(base_type) = new(base_type, Vector{Function}(), nothing)
end
#const VTableSpec = _VTableSpec{VTable}

@memoize function vtable_spec(t::Type{T})::VTableSpec where T
    return VTableSpec(T)
end
#@memoize function vtable(::Type{T}, ::Type{ParentT}) where {T, ParentT}
#    spec = vtable_spec(ParentT)
#    vtable = VTable(T, spec, Ptr{Cvoid}[])
#    #push!(spec.instantiations, vtable)
#    return vtable
#end

function _declare_virtual_method!(spec::VTableSpec, func)::Int
    if (func in spec.functions)
        @info "skipping redeclaration of virtual function, $func"
        return findfirst(==(func), spec.functions)
    end
    push!(spec.functions, func)
    return length(spec.functions)
end

function _define_virtual_method!(spec::VTableSpec, vtable::VTable, func, f_ptr)
    @assert (func in spec.functions) "function $func not declared as virtual for type $(spec.base_type)"
    idx = findfirst(==(func), spec.functions)
    vtable.func_ptrs[idx] = f_ptr
    return idx
end

end # module