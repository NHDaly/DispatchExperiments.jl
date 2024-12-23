@testitem "Hash Interface" begin
    @base abstract type Hashable end
    @virtual Hashable function fast_hash(this, h::UInt)::UInt end

    const hash_type_const = hash("MyArray")
    @extend struct MyArray{T} <: Hashable
        data::Vector{T}
        @override function fast_hash(this, h::UInt)::UInt
            h &= hash_type_const
            for x in this.data
                h = @polymorphic fast_hash(x, h)
            end
            return h
        end
    end

    @extend struct MyInt <: Hashable
        x::Int
        @override function fast_hash(this, h::UInt)::UInt
            hash(this.x, h)
        end
    end
    @extend struct MyFloat <: Hashable
        x::Float64
        @override function fast_hash(this, h::UInt)::UInt
            hash(this.x, h)
        end
    end

    @test fast_hash(MyInt(1), UInt(0)) == hash(1, UInt(0))

    a = MyArray{Any}([rand((MyInt(1), MyFloat(2.0))) for _ in 1:1000])

    @test fast_hash(a, UInt(0)) isa UInt
    @test @allocated(fast_hash(a, UInt(0))) == 0
end
