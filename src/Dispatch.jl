module Dispatch

include("single-dispatch.jl")
export SingleDispatch
using .SingleDispatch

export @base, @extend, @virtual, @overload, @polymorphic

end # module Dispatch
