module InterfaceImplementations

export @interface, @implement

using MacroTools

macro interface(T_name, block)
    function_defs = block.args
    function_names = []
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
        push!(function_arg_names, arg_names[2:end])
        push!(function_arg_types, arg_types[2:end])
        push!(function_return_vals, freturn)
    end

    ImplStructName = Symbol(T_name, "Implementation")
    impl_func_ptr_fields = [:($(fname)::Ptr{Cvoid}) for fname in function_names]
    obj_arg = gensym("obj")


    wrapper_function_defs = [
        begin
            fullargs = [:($arg_name::$arg_type) for (arg_name, arg_type) in zip(farg_names, farg_types)]
            :(function $(fname)($(obj_arg)::$(T_name), $(fullargs...))::$(freturn)
                ccall($(obj_arg).callbacks.$(fname), $(freturn),
                      (Ptr{Cvoid}, $(farg_types...),), $(obj_arg).instance, $(farg_names...))
            end)
        end
        for (fname, farg_names, farg_types, freturn) in
            zip(function_names, function_arg_names, function_arg_types, function_return_vals)
    ]

    esc(Base.remove_linenums!(quote
        # Will be a single instance (flyweight pattern) for each implementation struct.
        # Mutable so that we can store only a *pointer* to this single instance.
        mutable struct $(ImplStructName)
            $(impl_func_ptr_fields...)
        end

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


macro implement(interfaces, struct_def)
    @capture(interfaces, {interface_names__}) ||
        error("""Expected interface names in `{}`. Got: $interfaces.
            Usage: @implement {Interface1, Interface2, ...} struct MyStruct ... end
            """)
    interface_name = only(interface_names)

    @capture(struct_def, (mutable struct T_name_ body__ end | struct T_name_ body__ end)) ||
        error("""Expected struct definition. Got: $struct_def.""")

    ismutable = struct_def.args[1]

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
    function_arg_names = []
    function_arg_types = []
    function_return_vals = []

    for def in body_override_exprs
        def isa LineNumberNode && continue

        match = @capture(def,
            (function fname_(fargs__)::freturn_  fbody_  end) | (fname_(fargs__)::freturn_ = fbody__))
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

        @assert arg_types[1] == T_name "First argument of an override function must be the implementation type. Got $(arg_types[1]) in $(def)."

        push!(function_names, fname)
        push!(function_arg_names, arg_names[2:end])
        push!(function_arg_types, arg_types[2:end])
        push!(function_return_vals, freturn)
    end



    ImplInstanceName = Symbol(T_name, interface_name, "Implementation")
    ImplStructName = Symbol(interface_name, "Implementation")

    obj_name = gensym("obj")
    wrapper_callbacks = [  # (name, def)
        begin
            wrapper_name = Symbol("$(T_name)_$(interface_name)_impl__$(fname)")
            farg_exprs = [:($arg_name::$arg_type) for (arg_name, arg_type) in zip(farg_names, farg_types)]
            f = :(function $wrapper_name(instance::Ptr{Cvoid}, $(farg_exprs...))
                $obj_name = unsafe_pointer_to_objref(reinterpret(Ptr{$T_name}, instance))::$T_name
                return @inline $fname($obj_name, $(farg_names...))
            end)
            (wrapper_name, f)
        end
        for (fname, farg_names, farg_types, freturn) in
            zip(function_names, function_arg_names, function_arg_types, function_return_vals)
    ]

    wrapper_function_defs = [
        begin
            #@show fname, farg_types, freturn
            # Expr(:macrocall, Symbol("@cfunction"), fname, freturn, :((Ptr{Cvoid}, $(farg_types...)),))
            wrapper_name = wrapper_callback[1]
            :(@cfunction($wrapper_name, $freturn, (Ptr{Cvoid}, $(farg_types...),)))
        end
        for (wrapper_callback, farg_types, freturn) in
            zip(wrapper_callbacks, function_arg_types, function_return_vals)
    ]


    convert_def = if ismutable
        :(function Base.convert(::Type{$interface_name}, obj::$T_name)::$interface_name
            $interface_name($ImplInstanceName, pointer_from_objref(obj), obj)
        end)
    else
        # TODO
        error("Only supports mutable structs for now")
    end


    esc(Base.remove_linenums!(quote
        $struct_def

        $(body_override_exprs...)

        $((def for (_,def) in wrapper_callbacks)...)

        # TODO: Check function types against type check const from interface

        # We eval this const, so that the functions above are defined earlier.
        const $(ImplInstanceName) = eval($(QuoteNode(:($ImplStructName(
            $(wrapper_function_defs...)
        )))))

        $convert_def

        $T_name
    end))


end

# Example usage to test the macro
# @interface GameObjectInterface begin
#    @virtual function update(::GameObjectInterface, dt::Int)::Bool end
#    @virtual function render(::GameObjectInterface, renderer)::Nothing end
# end

end # module
