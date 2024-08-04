struct ObserveEventCallback
    f::Ptr{Cvoid}
    data::Ptr{Cvoid}
    data_ref::Any  # root data to prevent GC
end
function call_callback(c::ObserveEventCallback, event_type, event_data)
    @ccall $(c.f)(c.data::Ptr{Cvoid}, event_type::Cint, event_data::Cint)::Nothing
end


#-------------

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
    return ObserveEventCallback(
        @cfunction(achievements_observe_event_callback, Nothing, (Ptr{Cvoid},Int,Int)),
        pointer_from_objref(achievements),
        achievements,
    )
end

#-------------

struct PhysicsSystem
    # ...
    observers::Vector{ObserveEventCallback}
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
