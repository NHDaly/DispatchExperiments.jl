
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

@inline Base.empty!(d::LockedDict) = @lock d.lock empty!(d.dict)
