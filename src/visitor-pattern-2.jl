# This file is a manual implementation of single-dispatch.
module Visitors

abstract type Pastry end

mutable struct Beignet <: Pastry
    vtable1::Ptr{Cvoid}  # unused for now
    vtable2::Ptr{Cvoid}  # nameof(this)
end

mutable struct Cruller <: Pastry
    vtable1::Ptr{Cvoid}  # unused for now
    vtable2::Ptr{Cvoid}  # nameof(this)
end

# A bunch of pastry types to prvent any funny-business optimizations
struct A1 <: Pastry end
struct A2 <: Pastry end
struct A3 <: Pastry end
struct A4 <: Pastry end
struct A5 <: Pastry end
struct A6 <: Pastry end
struct A7 <: Pastry end
struct A8 <: Pastry end
struct A9 <: Pastry end
struct A10 <: Pastry end


function nameofBeignet(this::Ptr{Cvoid})
    push!(global_output[], "Beignet")
    nothing
end
function nameofCruller(this::Ptr{Cvoid})
    push!(global_output[], "Cruller")
    nothing
end
@inline function nameof(@nospecialize(pastry::Pastry))
    #p = Ref(pastry)
    #GC.@preserve p begin
        pp = pointer_from_objref(pastry)
        vtable2 = unsafe_load(reinterpret(Ptr{Ptr{Cvoid}}, pp), 2)
        v = ccall(vtable2, Nothing, (Ptr{Cvoid},), pp)
    #end
    v
end


Beignet() = Beignet(
    C_NULL,
    @cfunction(nameofBeignet, Nothing, (Ptr{Cvoid},)),
)
Cruller() = Cruller(
    C_NULL,
    @cfunction(nameofCruller, Nothing, (Ptr{Cvoid},)),
)

function nameof2(::Beignet)
    push!(global_output[], "Beignet")
    nothing
end
function nameof2(::Cruller)
    push!(global_output[], "Cruller")
    nothing
end
nameof2(::A1) = nothing
nameof2(::A2) = nothing
nameof2(::A3) = nothing
nameof2(::A4) = nothing
nameof2(::A5) = nothing

const global_output = Ref(String[])


pastries = [rand((Beignet(), Cruller())) for _ in 1:10]

using Profile
function foo()
    let ps = Visitors.pastries
        Visitors.global_output[] = String[]
        for p::Pastry in ps
            #Profile.@profile for _ in 1:1_000_000;
            for _ in 1:1_000_000;
                @inline Visitors.nameof(p)
            end
        end
    end
end
function foo2()
    let ps = Visitors.pastries
        Visitors.global_output[] = String[]
        for p::Pastry in ps
            #Profile.@profile for _ in 1:1_000_000;
            for _ in 1:1_000_000;
                Visitors.nameof2(p)
            end
        end
    end
end

end