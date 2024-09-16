module Dispatch

include("single-dispatch.jl")
export SingleDispatch
using .SingleDispatch

export @base, @extend, @virtual, @overload, @polymorphic

include("InterfaceImplementations/InterfaceImplementations.jl")
using .InterfaceImplementations
export @interface, @implement

end # module Dispatch
