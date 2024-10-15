@testitem "hash-vect" begin
    using BenchmarkTools

    const N = 1000

    @testset "regular vector" begin
        v = Any[i for i in 1:N]

        @btime hash($v)  # 11 μs 1001 allocations
    end

    @interface HashableInterface begin
        @virtual function Base.hash(x::HashableInterface, h::UInt)::UInt end
    end
    @implement {HashableInterface} mutable struct Hashable{T}
        x::T
        @override function Base.hash(x::Hashable{T}, h::UInt)::UInt where {T}
            return hash((x.x)::T, h)
        end
    end
    # @implement {HashableInterface} mutable struct Hashable
    #     x::Any
    #     T::Type
    #     @override function Base.hash(x::Hashable, h::UInt)::UInt
    #         return hash((x.x)::x.T, h)
    #     end
    #     Hashable(x::T) where {T} = new(x, T)
    # end

    @testset "fast vector" begin
        v = HashableInterface[Hashable(i) for i in 1:N]

        @btime hash($v)  # 11 μs 1001 allocations
    end
end
