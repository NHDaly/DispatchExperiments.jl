#=============================
Some Notes:

- Since these closures are inherently opaque, they prevent optimizations julia could
otherwise do. So sometimes, this will be slower than julia's built-in dynamic multiple
dispatch.
    - For example, if the function actually only has one method-instance, the dispatch
      can compile away entirely, even if the arguments' types are unknown.


Fairest best-case for julia dispatch comparison yet:
```julia
julia> @interface TestInterface5 begin
           @virtual function bumpX!(::TestInterface5)::Nothing end
       end
TestInterface5

julia> @implement {TestInterface5} mutable struct TestImpl5
           x::Int
           @override function getX(this::TestImpl5)::Nothing
               this.x += 1
               nothing
           end
       end

julia> obj = TestImpl5(10); @btime for _ in 1:1000  @noinline bumpX!($(obj)) end
  1.896 μs (0 allocations: 0 bytes)

julia> obj = TestImpl5(10); @btime for _ in 1:1000  @noinline bumpX!($([obj])[1]) end
  2.639 μs (0 allocations: 0 bytes)

julia> obj = TestImpl5(10); @btime for _ in 1:1000  @noinline bumpX!($(Any[obj])[1]) end
  8.458 μs (0 allocations: 0 bytes)

julia> obj = TestImpl5(10); @btime for _ in 1:1000  @noinline bumpX!($(TestInterface5[obj])[1]) end
  4.327 μs (0 allocations: 0 bytes)
```
Roughly an extra 1.7 ns overhead per call (4.3 - 2.6), over the ~2ns overhead of a single
function call. Not bad.

#-------------------------------------------------------------------

Lesson learned:
- ccall() with arg type `::T` *always copies T* as a pass-by-value.
    - If you want to pass through a reference to the original mutable obj, you should pass
      it as `Any`, to simulate passing by a pointer.
    - But isbits types should stay `::T`, to avoid the allocations.
    - I *think* this is as simple as `if isimmutable(T) T else Any end`...
        - But we don't know this at macro parse time....... I wonder if we can put it in
          the compiled code?

=============================#

module InterfaceImplementations

include("utils.jl")

export @interface, @implement

using MacroTools

macro interface(T_name, block)
    function_defs = block.args
    function_names = []
    function_var_names = []  # If fname is an expression (e.g. Base.foo), make it a var"".
    function_arg_names = []
    function_arg_types = []
    function_return_vals = []
    for def in function_defs
        if def isa LineNumberNode
            continue
        end
        match = @capture(def,
            @virtual function fname_(fargs__)::freturn_  fbody_  end)
        @assert match "Got unsupported definition: $(def). Should be `@virtual function name(::$(T_name), args...)::T end"
        # assert no body
        @assert isempty((ex for ex in fbody.args if !(ex isa LineNumberNode))) "Virtual function declarations must not have a body. Got $(def)."

        # @show fname, fargs, freturn

        arg_names = []
        arg_types = []
        for (i,arg) in enumerate(fargs)
            match = @capture(arg,
                arg_name_::arg_type_
            ) || @capture(arg,
                ::arg_type_
            ) || error("@virtual functions must supply types for all arguments via `::`. Found $(arg) in $(def).")

            arg_name === nothing && (arg_name = Symbol("arg$i"))
            push!(arg_types, arg_type)
            push!(arg_names, arg_name)
        end

        # TODO: Does it need to be the first? Could it be anywhere? :)
        @assert arg_types[1] == T_name "First argument of a virtual function must be the interface type. Got $(arg_types[1]) in $(def)."

        push!(function_names, fname)
        push!(function_var_names, Symbol(fname))
        push!(function_arg_names, arg_names[2:end])
        push!(function_arg_types, arg_types[2:end])
        push!(function_return_vals, freturn)
    end

    ImplStructName = Symbol(T_name, "Implementation")
    impl_func_ptr_fields = [:($(fname_var)::Ptr{Cvoid}) for fname_var in function_var_names]
    obj_arg = gensym("obj")


    wrapper_function_defs = [
        begin
            fullargs = [:($arg_name::$arg_type) for (arg_name, arg_type) in zip(farg_names, farg_types)]
            :(function $(fname)($(obj_arg)::$(T_name), $(fullargs...))::$(freturn)

                $(@__MODULE__()).do_ccall(
                        $(obj_arg).callbacks.$(fname_var), $(obj_arg).instance,
                        $(freturn), Tuple{$(farg_types...)}, $(farg_names...))
            end)
        end
        for (fname, fname_var, farg_names, farg_types, freturn) in
            zip(function_names, function_var_names, function_arg_names, function_arg_types, function_return_vals)
    ]

    init_func = :(function $(Symbol("init_$(ImplStructName)!"))(vtable, $(function_var_names...))
            $((
                :(vtable.$(fname_var) = $(fname_var))
                for fname_var in function_var_names
            )...)
        end)

    esc(Base.remove_linenums!(quote
        # Will be a single instance (flyweight pattern) for each implementation struct.
        # Mutable so that we can store only a *pointer* to this single instance.
        mutable struct $(ImplStructName)
            $(impl_func_ptr_fields...)
        end

        $(init_func)

        # TODO: Add type checking const

        struct $T_name
            callbacks::$(ImplStructName)
            instance::Ptr{Cvoid}
            instance_ref::Any
        end

        $(wrapper_function_defs...)

        $T_name
    end))
end

@generated function do_ccall(f, instance, ::Type{RT}, ::Type{ArgTypes}, args...) where {RT, ArgTypes}
    # Core.println(ArgTypes)
    carg_types = to_C_type.(fieldtypes(ArgTypes))

    # Core.println(carg_types)
    expr = :(
        ccall(f, RT, (Ptr{Cvoid},
        $(carg_types...),), instance,
        $((:(args[$i]) for i in 1:length(args))...))
    )
    #Core.println(expr)
    return expr
end
function to_C_type(::Type{T}) where T
    if T == String
        return Cstring
    elseif ismutabletype(T)
        return Any
    else
        return T
    end
end

macro implement(interfaces, struct_def)
    @capture(interfaces, {interface_names__}) ||
        error("""Expected interface names in `{}`. Got: $interfaces.
            Usage: @implement {Interface1, Interface2, ...} struct MyStruct ... end
            """)
    interface_name = only(interface_names)

    @capture(struct_def,
        (mutable struct T_name_{Params__} body__ end) | (mutable struct T_name_ body__ end)
        | (      struct T_name_{Params__} body__ end) | (        struct T_name_ body__ end)
    ) || error("""Expected struct definition. Got: $struct_def.""")

    ismutable = struct_def.args[1]
    has_params = Params !== nothing && !isempty(Params)

    body_keep_exprs = []
    body_override_exprs = []

    for expr in body
        if @capture(expr, @override fexpr_)
            push!(body_override_exprs, fexpr)
        else
            push!(body_keep_exprs, expr)
        end
    end

    struct_def.args[3].args = body_keep_exprs

    function_names = []
    function_var_names = []  # If fname is an expression (e.g. Base.foo), make it a var"".
    function_arg_names = []
    function_arg_types = []
    function_return_vals = []
    function_where_clauses = []

    for def in body_override_exprs
        def isa LineNumberNode && continue

        match = @capture(def,
            (function fname_(fargs__)::freturn_ fbody_ end) |
            (function fname_(fargs__)::freturn_ where {WhereTypes__} fbody_ end) |
            (fname_(fargs__)::freturn_ = fbody_) |
            (fname_(fargs__)::freturn_ where {WhereTypes__} = fbody_)
        )
        @assert match """Got unsupported definition: `@override $def`.
            Usage: `@override function fname(::$(T_name), args...)::T ... end`"""

        # @show fname, fargs, freturn

        arg_names = []
        arg_types = []
        for (i,arg) in enumerate(fargs)
            match = @capture(arg,
                arg_name_::arg_type_
            ) || @capture(arg,
                ::arg_type_
            ) || error("Functions must supply types for all arguments via `::`. Found $(arg) in $(def).")

            arg_name === nothing && (arg_name = Symbol("arg$i"))
            push!(arg_types, arg_type)
            push!(arg_names, arg_name)
        end

        arg1 = arg_types[1]
        @assert(arg1 == T_name || arg1 isa Expr && arg1.args[1] == T_name,
            "First argument of a virtual function must be the interface type. Got $(arg_types[1]) in $(def). Expected $T_name.")

        push!(function_names, fname)
        push!(function_var_names, Symbol(fname))
        push!(function_arg_names, arg_names[2:end])
        push!(function_arg_types, arg_types[2:end])
        push!(function_return_vals, freturn)
        push!(function_where_clauses, WhereTypes)
    end



    ImplInstanceName = Symbol(T_name, interface_name, "Implementation")
    ImplStructName = Symbol(interface_name, "Implementation")

    obj_name = gensym("obj")
    wrapper_callbacks = [  # (name, def)
        begin
            wrapper_name = Symbol("$(T_name)_$(interface_name)_impl__$(fname)")
            farg_exprs = [:($arg_name::$arg_type) for (arg_name, arg_type) in zip(farg_names, farg_types)]
            # TODO: Handle these separately. For now they're the same.
            # f = if isempty(Params)
                f = :(function $wrapper_name(instance::Ptr{Cvoid}, $(farg_exprs...))::$freturn
                    $obj_name = unsafe_pointer_to_objref(reinterpret(Ptr{$T_name}, instance))::$(T_name)
                    return @inline $fname($obj_name, $(farg_names...))
                end)
            # else
            #     :(function $wrapper_name(instance::Ptr{Cvoid}, @nospecialize(::Type{T}), $(farg_exprs...))::$freturn where {T}
            #         $obj_name = unsafe_pointer_to_objref(reinterpret(Ptr{$T_name}, instance))::$T
            #         return @inline $fname($obj_name, $(farg_names...))
            #     end)
            # end
            (wrapper_name, f)
        end
        for (fname, farg_names, farg_types, freturn) in
            zip(function_names, function_arg_names, function_arg_types, function_return_vals)
    ]

    wrapper_function_defs = [
        begin
            #@show fname, farg_types, freturn
            # Expr(:macrocall, Symbol("@cfunction"), fname, freturn, :((Ptr{Cvoid}, $(farg_types...)),))
            evaled_arg_types = Tuple(Core.eval(__module__, arg_type) for arg_type in farg_types)
            carg_types = to_C_type.(evaled_arg_types)
            wrapper_name = wrapper_callback[1]
            (Symbol("construct_$wrapper_name"), :(
                # $(@__MODULE__()).cfunction(Val($wrapper_name), $freturn, Tuple{Ptr{Cvoid}, $(farg_types...)})
                #carg_types = Tuple($((:(to_C_type(t)) for t in farg_types)...));
                @cfunction($wrapper_name, $freturn, (Ptr{Cvoid}, $(carg_types...)))
            ))
        end
        for (wrapper_callback, farg_types, freturn) in
            zip(wrapper_callbacks, function_arg_types, function_return_vals)
    ]
    toplevel_cfunction_constructors = [
        begin
            :($constructor_name() = $f)
        end
        for (constructor_name, f) in wrapper_function_defs
    ]

    init_func = Symbol("init_$(ImplStructName)!")

    reinit_func = Symbol("reinit_$(ImplStructName)!")
    reinit_func_def = :(function $(reinit_func)()
            #if $(ImplInstanceName).$(first(function_var_names)) === C_NULL
            #    $(init_func)($(ImplInstanceName),
            #        $((
            #            begin
            #                constructor_name = wrapper_def[1]
            #                :($(__module__).$(constructor_name)())
            #            end
            #            for wrapper_def in wrapper_function_defs
            #        )...))
            #end
        end)


    convert_def = if ismutable
        if !has_params
            :(function Base.convert(::Type{$interface_name}, obj::$T_name)::$interface_name
                $reinit_func()
                $interface_name($ImplInstanceName, pointer_from_objref(obj), obj)
            end)
        else
            # For structs with type parameters, we need to pass the concrete type through.
            :(function Base.convert(::Type{$interface_name}, obj::$T_name)::$interface_name
                $reinit_func()
                $interface_name($ImplInstanceName, pointer_from_objref(obj), obj)
            end)
        end
    else
        # TODO
        error("Only supports mutable structs for now")
    end

    esc(Base.remove_linenums!(quote
        $struct_def

        $(body_override_exprs...)

        $((def for (_,def) in wrapper_callbacks)...)

        # TODO: Check function types against type check const from interface

        $reinit_func_def

        $(toplevel_cfunction_constructors...)

        # We eval this const, so that the functions above are defined earlier.
        const $(ImplInstanceName) = eval($(QuoteNode(:($ImplStructName(
            $((:(Ptr{Cvoid}(C_NULL)) for f in first.(wrapper_function_defs))...)
        )))))
        # # We eval this const, so that the functions above are defined earlier.
        # const $(ImplInstanceName) = eval($(QuoteNode(:($ImplStructName(
        #     $((:($f()) for f in first.(wrapper_function_defs))...)
        # )))))

        #eval($(QuoteNode(:(module $(Symbol("___vtable_init_$(ImplInstanceName)"))
        #    using ..$(nameof(__module__)): $(ImplInstanceName), $(init_func)

        #    function __init__()
        #    end
        #end))))

        $convert_def

        $T_name
    end))


end

# UGH: a generated function here introduces allocations after Module load.
@generated function cfunction(::Val{F}, ::Type{RT}, ::Type{ArgTypes}) where {F, RT, ArgTypes}
    Core.println(ArgTypes)

    carg_types = to_C_type.(fieldtypes(ArgTypes))
    #Core.println(carg_types)

    expr =:( @cfunction($F, $RT, ($(carg_types...),)) )
    #Core.println(expr)

    return expr
end

# Example usage to test the macro
# @interface GameObjectInterface begin
#    @virtual function update(::GameObjectInterface, dt::Int)::Bool end
#    @virtual function render(::GameObjectInterface, renderer)::Nothing end
# end

end # module
