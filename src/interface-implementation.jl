module InterfaceImplementations

export @interface

using MacroTools

macro interface(name, block)
    function_defs = block.args
    function_names = []
    # TODO: Actually i think named args is all i need, since they're type-asserted at ccall
    function_arg_names = []
    function_arg_types = []
    function_return_vals = []
    for def in function_defs
        if def isa LineNumberNode
            continue
        end
        match = @capture(def,
            @virtual function fname_(fargs__)::freturn_  fbody_  end)
        @assert match "Got unsupported definition: $(def). Should be `@virtual function name(::$(name), args...)::T end"
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
        @assert arg_types[1] == name "First argument of a virtual function must be the interface type. Got $(arg_types[1]) in $(def)."

        push!(function_names, fname)
        push!(function_arg_names, arg_names[2:end])
        push!(function_arg_types, arg_types[2:end])
        push!(function_return_vals, freturn)
    end

    ImplStructName = Symbol(name, "Implementation")
    impl_func_ptr_fields = [:($(fname)::Ptr{Cvoid}) for fname in function_names]
    obj_arg = gensym("obj")


    wrapper_function_defs = [
        begin
            fullargs = [:($arg_name::$arg_type) for (arg_name, arg_type) in zip(farg_names, farg_types)]
            :(function $(fname)($(obj_arg)::$(name), $(fullargs...))::$(freturn)
                ccall($(obj_arg).callbacks.$(fname), $(freturn), ($(farg_types...),), $(farg_names...))
            end)
        end
        for (fname, farg_names, farg_types, freturn) in
            zip(function_names, function_arg_names, function_arg_types, function_return_vals)
    ]

    esc(quote
        # Will be a single instance (flyweight pattern) for each implementation struct.
        # Mutable so that we can store only a *pointer* to this single instance.
        mutable struct $(ImplStructName)
            $(impl_func_ptr_fields...)
        end

        struct $name
            callbacks::$(ImplStructName)
            instance::Ptr{Cvoid}
            instance_ref::Any
        end

        $(wrapper_function_defs...)

        $name
    end)
end

# Example usage to test the macro
# @interface GameObjectInterface begin
#    @virtual function update(::GameObjectInterface, dt::Int)::Bool end
#    @virtual function render(::GameObjectInterface, renderer)::Nothing end
# end

end # module
