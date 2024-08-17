"""
    @interface Observer begin
        @virtual function observe_event(::Observer, ::Int, ::Int)::Nothing end
        @virtual function observee_destructing(::Observer)::Nothing end
    end
"""
macro interface(name)
    esc(quote
        struct $name end
    end)
end

"""
    @implement{Observer} struct Achievements

        # ...

        @override function observe_event(a::Achievements, event_type::Int, data::Int)
            # ...
        end
        @override function observee_destructing(a::Achievements)
            # ...
        end
    end
"""
macro implement(interface, struct_def)
    @assert interface.head == :braces
    interfaces = interface.args
    #for interface in interfaces
    interface = only(interfaces) # for now
    struct_name = get_struct_name(struct_def.args[2])
    impl_name = Symbol("$(struct_name)$(interface)Impl")
    overrides, struct_def = extract_override_funcs!(struct_def)
    ismutable = struct_def.args[1]
    impls = [
        :(
            @cfunction($(fname(f)), Nothing, $(ftypes(f)))
        )
        for f in overrides
    ]
    #@show impls
    esc(quote
        $(struct_def)
        $(overrides...)
        # TODO: If you try to define this top-level, it fails because overrides hasn't been
        # evaluated yet..... maybe we need to stage it? Making it a function does that,
        # but then it'd get a different function pointer every time, which defeats the purpose.
        const $impl_name() = $interface(
            $(impls...),
        )
        $(if ismutable
            quote
                make_interface_callbacks(::$interface, i::$(struct_name)) = ObserveEventInterface(
                    $impl_name(),
                    pointer_from_objref(i),
                    i,
                )
            end
        else
            quote
                function make_interface_callbacks(::$interface, i::$(struct_name))
                    r = Ref(i)
                    ObserveEventInterface(
                        $impl_name,
                        pointer_from_objref(r),
                        r,
                    )
                end
            end
        end)
    end)
end
get_struct_name(name_expr::Expr) = name_expr.args[1]
get_struct_name(name::Symbol) = name
fname(fexpr) = fexpr.args[1].args[1].args[1]
ftypes(fexpr) = :(())  # TODO

function extract_override_funcs!(struct_def)
    virtual_funcs = []
    struct_body = struct_def.args[3]
    for i in 1:length(struct_body.args)
        arg = struct_body.args[i]
        if arg === nothing || arg isa LineNumberNode
            continue
        end
        #dump(arg)
        if arg.head == :macrocall && arg.args[1] == Symbol("@override")
            push!(virtual_funcs, arg.args[end])
            struct_body.args[i] = nothing
        end
    end
    #@show virtual_funcs
    return virtual_funcs, struct_def
end

macro override(args...) nothing end

#---------------


struct CustomClosure
    f::Ptr{Cvoid}
    data::Ptr{Cvoid}
    data_ref::Any  # root data to prevent GC
end
function call_callback(c::CustomClosure, event_type, event_data)
    @ccall $(c.f)(c.data::Ptr{Cvoid}, event_type::Cint, event_data::Cint)::Nothing
end

mutable struct ObserveEventInterfaceImplementation
    observe_event::Ptr{Cvoid}
    init_callback::Ptr{Cvoid}
    observee_destructing::Ptr{Cvoid}
end

struct ObserveEventInterface
    callbacks::ObserveEventInterfaceImplementation
    instance::Ptr{Cvoid}
    instance_ref::Any
end

function observe_event(c::ObserveEventInterface, event_type, event_data)
    @ccall $(c.callbacks.observe_event)(c.instance::Ptr{Cvoid}, event_type::Cint, event_data::Cint)::Nothing
end
function init_callback(c::ObserveEventInterface)
    @ccall $(c.callbacks.init_callback)(c.instance::Ptr{Cvoid})::Nothing
end
function observee_destructing(c::ObserveEventInterface)
    @ccall $(c.callbacks.observee_destructing)(c.instance::Ptr{Cvoid})::Nothing
end

#-------------

#=
const AchievementsObserveEventInterfaceImplementation = ObserveEventInterfaceImplementation(
    @cfunction(achievements_observe_event_callback, Nothing, (Ptr{Cvoid},Int,Int)),
    C_NULL,
    C_NULL,
)


mutable struct Achievements
    #achievements::Set{String}
    count::Int
end
achieve!(a, event_data) = a.count += 1

function achievements_observe_event(achievements::Achievements, event_type, event_data)
    #@show event_type
    if event_type == 1
        achieve!(achievements, event_data)
    end
    return nothing
end
function achievements_observe_event_callback(data, event_type, event_data)
    #println(typeof(data))
    #@info "got" data
    achievements = unsafe_pointer_to_objref(reinterpret(Ptr{Achievements}, data))::Achievements
    #println(pointer_from_objref(achievements))
    return @inline achievements_observe_event(achievements, event_type, event_data)
end

function get_achievements_event_callback(achievements)
    #@info "create callback" pointer_from_objref(achievements)
    return CustomClosure(
        @cfunction(achievements_observe_event_callback, Nothing, (Ptr{Cvoid},Int,Int)),
        pointer_from_objref(achievements),
        achievements,
    )
end

#-------------

struct PhysicsSystem
    # ...
    observers::Vector{CustomClosure}
end

function physics_system_observe_event(physics_system::PhysicsSystem, event_type, event_data)
    for observer in physics_system.observers
        call_callback(observer, event_type, event_data)
    end
end

# --------------------

using Main.Profile,Main.PProf, Main.BenchmarkTools
function profiling()
    global a = Achievements(0)
    global p = PhysicsSystem([])
    let a = a, p = p
        #println(pointer_from_objref(a))
        c = get_achievements_event_callback(a)
        for _ in 1:100
            push!(p.observers, c)
        end

        physics_system_observe_event(p, 1, 1)
        r = rand(Int32)
        @time physics_system_observe_event(p, r, r)
        @btime physics_system_observe_event($p, $(r), $(r))
        Profile.clear(); @profile for _ in 1:1_000_000 physics_system_observe_event(p, r, r) end; pprof(webport=23223)
        # Profile.Allocs.clear(); Profile.Allocs.@profile for _ in 1:1_000_000 physics_system_observe_event(p, r, r) end; PProf.Allocs.pprof(webport=23224)
    end
    @show a.count
end
=#
