# Interface:

# Mutable so that we have only a *pointer* to the one shared instance. (In case there are
# tens of function interfaces in this Interface, to prevent the fat-pointer from being too
# fat.)
mutable struct HashableInterfaceVTable
    var"Base.hash"::Union{Ptr{Cvoid}, Base.CFunction}
end
# The "fat pointer" to the dynamic object. immutable, so inline-allocated in a vector.
struct HashableInterface
    callbacks::HashableInterfaceVTable
    instance_ref::Any
end
function Base.hash(obj::HashableInterface, h::UInt)::UInt
    f = obj.callbacks.var"Base.hash"
    instance = pointer_from_objref(obj.instance_ref)
    f isa Base.CFunction && (f = f.ptr)
    return ccall(f, UInt, (Ptr{Cvoid}, UInt), instance, h)
end

# Implementation of the interface (parameterized on a specific object type).
mutable struct Hashable{T}
    x::T
end
function (Base.hash(x::Hashable{T}, h::UInt)::UInt) where T
    return hash(x.x::T, h)
end

# We need to create exactly one vtable per instantiation of the Hashable implementation.
# Since julia doesn't give us a chance to create a global-const VTable per instantiation of
# this template, we ask the compiler to create one, and cache it for us.
# Since the arguments to this function are only compiler-constants (a Type), we should be
# able to constant-fold this definition, and always return the same shared instance.

# We need to compile a new function for each type. This is the equivalent of putting the
# typename<T> on a struct's methods in C++. But unlike C++ we can't instantiate compilations
# when a struct is instantiated, so we need to do so using this closure generator.
function _HashableHashableInterfaceVTable(::Type{H}) where H
    # The function pointer casts from Ptr{Cvoid} back to the true type, H:
    f = (instance::Ptr{Cvoid}, h::UInt) -> begin
        obj = unsafe_pointer_to_objref(reinterpret(Ptr{H}, instance))::H
        return Base.hash(obj, h)::UInt
    end
    # Return the shared vtable instance
    return HashableInterfaceVTable(
        @cfunction($f, UInt, (Ptr{Cvoid}, UInt))
    )
end
# # I considered using a Generated function to enforce that this gets cached, but
# # I'd prefer to avoid that if possible. This seems like something that should fold
# # already. The main issue is serializing the opaque closure...
# @generated function HashableHashableInterfaceVTable(::Type{H}) where H
#     return _HashableHashableInterfaceVTable(H)
# end
# However, Jameson pointed out that caching mutable objects is really not the compiler's
# job, and that if you want to cache a mutable object, you should do it yourself, with a
# (locked) global dict. So that's what we've done here instead.
function HashableHashableInterfaceVTable(::Type{H}) where H
    v = get(vtables_dict, H, nothing)
    if v === nothing
        v = _HashableHashableInterfaceVTable(H)
        vtables_dict[H] = v
        return v
    end
    return v::HashableInterfaceVTable
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

const vtables_dict = LockedDict{DataType,HashableInterfaceVTable}()

function Base.convert(::Type{HashableInterface}, obj::Hashable)::HashableInterface
    HashableInterface(HashableHashableInterfaceVTable(typeof(obj)), obj)
end

function setup()
    N = 1000
    return HashableInterface[Hashable(i) for i in 1:N]
end
function bench(v)
    return hash(v)
end


