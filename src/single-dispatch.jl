module SingleDispatch

using Memoize
using MacroTools

"""
    @base abstract type BaseClass end
    @virtual BaseClass function func1(this::Ptr, arg1) ReturnType end
    @virtual BaseClass function func2(this::Ptr)::ReturnType end
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

#macro polymorphic(call::Expr)
#    @assert call.head == :call
#    this = call.args[2]
#    p = gensym(:p)
#    r = gensym(:r)
#    obj = gensym(:this)
#    call.args[2] = :(p
#    quote
#        @invoke
#        $obj = $this
#        local $r
#        $p = if $ismutable($obj)
#            $pointer_from_objref($obj)
#        else
#            $r = $Ref($obj)
#            $pointer_from_objref($r)
#        end
#        $GC.@preserve $r begin
#            $(call)
#        end
#    end)
#end


function _emit_virtual_func(__module__::Module, BaseType, spec, func_expr::Expr)
    name = func_expr.args[1].args[1].args[1]
    return_type = func_expr.args[1].args[2]
    func = Core.eval(__module__, :(function $name end))
    idx = _declare_virtual_method!(spec, func)
    #dump(BaseType)
    #@show BaseType, ismutabletype(BaseType)
    if ismutabletype(BaseType)
        return quote
            function $(esc(name))(this::$(esc(BaseType)))::$(esc(return_type))
                p = pointer_from_objref(this)
                vtable = unsafe_load(reinterpret(Ptr{VTable}, p), 1)
                f_ptr = vtable.func_ptrs[$idx]
                # TODO: arg types
                ccall(f_ptr, Int, (Ptr{Cvoid},), p)
            end
        end
    else
        return quote
            function $(esc(name))(this::$(esc(BaseType)))::$(esc(return_type))
                r = Ref(this)
                GC.@preserve r begin
                    p = pointer_from_objref(r)
                    vtable = unsafe_load(reinterpret(Ptr{VTable}, p), 1)
                    f_ptr = vtable.func_ptrs[$idx]
                    # TODO: arg types
                    ccall(f_ptr, Int, (Ptr{Cvoid},), p)
                end
            end
        end
    end
end

function _emit_override_func(__module__::Module, spec, vtable, type, func_expr::Expr)
    #@assert func_expr.args[1].args[1].args[2].args[2] === :(Ptr{$type})
    fname = gensym(:func)
    wrapper_name = gensym(:wrapper)
    f_ptr_name = gensym(:f_ptr)
    return esc(quote
        $fname = $func_expr
        function $wrapper_name(this::Ptr{Cvoid})
            o = unsafe_load(reinterpret(Ptr{$type}, this))
            return $fname(o)
        end
        # TODO: arg types
        const $f_ptr_name = @eval @cfunction($wrapper_name, Int, (Ptr{Cvoid},))
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