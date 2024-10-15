# TODO: What if we just make a CFunction closure around the object itself in the first place?
#  -- Update: Never mind it doesn't work. See `builtin-closures.jl` for results.

mutable struct HashableInterfaceImplementation
    # This was the second change: allow "closures" here.
    var"Base.hash"::Union{Ptr{Cvoid}, Base.CFunction}
end
struct HashableInterface
    callbacks::HashableInterfaceImplementation
    instance::Ptr{Cvoid}  # TODO delete this
    instance_ref::Any
end
function Base.hash(var"##obj#247"::HashableInterface, h::UInt)::UInt
    f = var"##obj#247".callbacks.var"Base.hash"
    f isa Base.CFunction && (f = f.ptr)
    ccall(f, UInt, (Ptr{Cvoid}, UInt), (var"##obj#247").instance, h)
end

mutable struct Hashable{T}
    x::T
end
function (Base.hash(x::Hashable{T}, h::UInt)::UInt) where T
    return hash(x.x::T, h)
end

# This was the key: Use a closure/lambda to capture the type of the object so that the
# callback can derefernce the pointer to a concrete type.
# We need to compile a new function for each type. This is the equivalent of putting the
# typename<T> on a struct's methods in C++. But unlike C++ we can't instantiate compilations
# when a struct is instantiated, so we need to do so using this closure generator.
function _HashableHashableInterfaceImplementation(::Type{H}) where H
    function (var"Hashable_HashableInterface_impl__Base.hash"(instance::Ptr{Cvoid}, h::UInt)::UInt)
        var"##obj#248" = unsafe_pointer_to_objref(reinterpret(Ptr{H}, instance))::H
        return begin
                @inline local var"#224#val" = Base.hash(var"##obj#248", h)
                var"#224#val"
            end
    end
    return HashableInterfaceImplementation(
        @cfunction($var"Hashable_HashableInterface_impl__Base.hash", UInt, (Ptr{Cvoid}, UInt))
    )
end
# # We use a generated function here to cache the vtable instance per type.
# @generated function HashableHashableInterfaceImplementation(::Type{H}) where H
#     return _HashableHashableInterfaceImplementation(H)
# end
function HashableHashableInterfaceImplementation(::Type{H}) where H
    v = get(vtables_dict, H, nothing)
    if v === nothing
        v = _HashableHashableInterfaceImplementation(H)
        vtables_dict[H] = v
        return v
    end
    return v::HashableInterfaceImplementation
end

struct LockedDict{K,V} <: AbstractDict{K,V}
    dict::Dict{K,V}
    lock::Threads.SpinLock
end
LockedDict{K,V}() where {K,V} = LockedDict{K,V}(Dict{K,V}(), Threads.SpinLock())
# For some weird reason this @inline is needed to infer through these correclty.
@inline Base.getindex(d::LockedDict, args...) = @lock d.lock getindex(d.dict, args...)
@inline Base.setindex!(d::LockedDict, args...) = @lock d.lock setindex!(d.dict, args...)
@inline Base.get(d::LockedDict, args...) = @lock d.lock get(d.dict, args...)
@inline Base.get!(d::LockedDict, args...) = @lock d.lock get!(d.dict, args...)

const vtables_dict = LockedDict{DataType,HashableInterfaceImplementation}()

function Base.convert(::Type{HashableInterface}, obj::Hashable)::HashableInterface
    HashableInterface(HashableHashableInterfaceImplementation(typeof(obj)), pointer_from_objref(obj), obj)
end

function setup()
    N = 1000
    return HashableInterface[Hashable(i) for i in 1:N]
end
function bench(v)
    return hash(v)
end








#-------- Experiments with eliminating allocations for the fixed mutable vtable. --------

# Specify how to compute some vector{T} of results
struct ComputationSpec{T}
    # args...
end

# Do the computation. Returns Vector{T}.
function compute(spec::ComputationSpec{T}) where {T}
    if is_noop(spec) # spec is noop, return empty vector
        # But return the _same_ empty vector always, to avoid allocations.
        #  (Let's say the caller promises not to mutate it.)
        return empty_vec(T)
    else
        # ... do the computation ...
    end
end
@generated empty_vec(::Type{T}) where {T} = T[]  # Constructs T[] each call..
is_noop(spec) = true  # for this example, always true

