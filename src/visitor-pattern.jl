module Visitors

abstract type Pastry end

struct Beignet <: Pastry
    vtable1::Ptr{Cvoid}  # accept(this, visitor)
    vtable2::Ptr{Cvoid}  # nameof(this)
end

struct Cruller <: Pastry
    vtable1::Ptr{Cvoid}
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


# interface PastryVisitor {
#     void visitBeignet(Beignet beignet);
#     void visitCruller(Cruller cruller);
# }
abstract type PastryVisitor end

function acceptBeignet(this::Ptr, visitor::Ptr)
    visitBeignet(visitor, this)
    nothing
end
function acceptCruller(this::Ptr, visitor::Ptr)
    visitCruller(visitor, this)
    nothing
end

function accept(pastry::Pastry, visitor::PastryVisitor)
    p = Ref(pastry)
    v = Ref(visitor)
    #p,v = pastry, visitor
    GC.@preserve p v begin
        pp, pv = pointer_from_objref(p), pointer_from_objref(v)
        ccall(pastry.vtable1, Nothing, (Ptr{Beignet}, Ptr{Cvoid}), pp, pv)
    end
    return nothing
end


function nameofBeignet(this::Ptr{Cvoid})::String
    return "Beignet"
end
function nameofCruller(this::Ptr{Cvoid})::String
    return "Cruller"
end
function nameof(pastry::Pastry)
    p = Ref(pastry)
    GC.@preserve p begin
        pp = pointer_from_objref(p)
        v = ccall(pastry.vtable2, String, (Ptr{Cvoid},), pp)
    end
    v
end


Beignet() = Beignet(
    @cfunction(acceptBeignet, Nothing, (Ptr{Beignet}, Ptr{Cvoid})),
    @cfunction(nameofBeignet, String, (Ptr{Cvoid},)),
)
Cruller() = Cruller(
    @cfunction(acceptCruller, Nothing, (Ptr{Cruller}, Ptr{Cvoid})),
    @cfunction(nameofCruller, String, (Ptr{Cvoid},)),
)

@enum Operation EatingBeignet BakingBeignet EatingCruller BakingCruller

struct EatVisitor <: PastryVisitor
    vtable1::Ptr{Cvoid}
    #---
    vtable2::Ptr{Cvoid}
    #output::Vector{Operation}
    # --
end
function eatVisitBeignet(vp::Ptr, beignet::Ptr)
    visitor = unsafe_load(reinterpret(Ptr{EatVisitor}, vp))
    #push!(visitor.output, EatingBeignet)
    push!(global_output[], EatingBeignet)
    nothing
end
function eatVisitCruller(vp::Ptr, cruller::Ptr)
    visitor = unsafe_load(reinterpret(Ptr{EatVisitor}, vp))
    #push!(visitor.output, EatingCruller)
    push!(global_output[], EatingCruller)
    nothing
end

# HACK
const global_output = Ref(Vector{Operation}())

struct BakeVisitor <: PastryVisitor
    vtable1::Ptr{Cvoid}
    vtable2::Ptr{Cvoid}
    #---
    #output::Vector{Operation}
end
function bakeVisitBeignet(vp::Ptr, beignet::Ptr)
    visitor = unsafe_load(reinterpret(Ptr{EatVisitor}, vp))
    #push!(visitor.output, BakingBeignet)
    push!(global_output[], BakingBeignet)
    nothing
end
function bakeVisitCruller(vp::Ptr, cruller::Ptr)
    visitor = unsafe_load(reinterpret(Ptr{EatVisitor}, vp))
    #push!(visitor.output, BakingCruller)
    push!(global_output[], BakingCruller)
    nothing
end

function visitBeignet(visitor::Ptr, beignet::Ptr{Beignet})
    vtable_ptr = reinterpret(Ptr{Ptr{Cvoid}}, visitor)
    vtable1 = unsafe_load(vtable_ptr, 1)
    ccall(vtable1, Nothing, (Ptr{Any}, Ptr{Any}), visitor, beignet)
end
function visitCruller(visitor::Ptr, cruller::Ptr{Cruller})
    vtable_ptr = reinterpret(Ptr{Ptr{Cvoid}}, visitor)
    vtable2 = unsafe_load(vtable_ptr, 2)
    ccall(vtable2, Nothing, (Ptr{Any}, Ptr{Any}), visitor, cruller)
end

EatVisitor() = EatVisitor(
    @cfunction(eatVisitBeignet, Nothing, (Ptr{Cvoid}, Ptr{Cvoid})),
    @cfunction(eatVisitCruller, Nothing, (Ptr{Cvoid}, Ptr{Cvoid})),
    #x,
)
BakeVisitor() = BakeVisitor(
    @cfunction(bakeVisitBeignet, Nothing, (Ptr{Cvoid}, Ptr{Cvoid})),
    @cfunction(bakeVisitCruller, Nothing, (Ptr{Cvoid}, Ptr{Cvoid})),
    #x,
)




function eat(output, pastry::Pastry)
    visitor = EatVisitor()
    accept(pastry, visitor)
    #return output
end
function bake(output, pastry::Pastry)
    visitor = BakeVisitor()
    accept(pastry, visitor)
    #return output
end

pastries = [rand((Beignet(), Cruller())) for _ in 1:10]
operations = [rand((eat, bake)) for _ in 1:100]


function eat2(output, ::Beignet)
    push!(output, EatingBeignet)
end
function eat2(output, ::Cruller)
    push!(output, EatingCruller)
end
function bake2(output, ::Beignet)
    push!(output, BakingBeignet)
end
function bake2(output, ::Cruller)
    push!(output, BakingCruller)
end

operations2 = [rand((eat2, bake2)) for _ in 1:100]

function nameof2(::Beignet)
    return "Beignet"
end
function nameof2(::Cruller)
    return "Cruller"
end


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