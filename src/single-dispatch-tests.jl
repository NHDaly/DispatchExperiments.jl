@testitem "Basic API" begin
# module M
#    using Dispatch
#    using Test
    Base.Experimental.@optlevel 2  # Force optimization for tests

    SingleDispatch.@base abstract type BaseClass end
    SingleDispatch.@virtual BaseClass function func1(this::Ptr)::Int end

    SingleDispatch.@extend struct DerivedClass <: BaseClass
        @override function func1(this::DerivedClass)::Int
            10
        end
    end

    const d = DerivedClass()

    @test SingleDispatch.@polymorphic(func1(d)) == func1(d) == 10
    # TODO: Fix this to be 0, after https://github.com/JuliaLang/julia/pull/50136.
    @test @allocated(SingleDispatch.@polymorphic func1(d)) == 16  # A single allocation

    SingleDispatch.@extend mutable struct MutDerivedClass <: BaseClass
        @override function func1(this::MutDerivedClass)::Int
            10
        end
    end

    const dm = MutDerivedClass()
    @test SingleDispatch.@polymorphic(func1(dm)) == func1(dm) == 10

    # NOTE: this fails in VSCode tests for some reason, but passes in the REPL.
    @test @allocated(SingleDispatch.@polymorphic func1(dm)) == 0

    run() = SingleDispatch.@polymorphic func1(d::DerivedClass)
end

@testitem "Basic API: multiple args" begin
# module M
#    using Dispatch
#    using Test
    Base.Experimental.@optlevel 2  # Force optimization for tests

    SingleDispatch.@base abstract type BaseClass end
    SingleDispatch.@virtual BaseClass function func1(this, x::Int, y::Int)::Int end

    SingleDispatch.@extend struct D1 <: BaseClass
        x::Int
        @override function func1(this::D1, x::Int, y::Int)::Int
            this.x + x + y
        end
    end

    const d = D1(10)

    @test SingleDispatch.@polymorphic(func1(d, 1, 2)) == func1(d, 1, 2) == 13
    # TODO: Fix this to be 0, after https://github.com/JuliaLang/julia/pull/50136.
    @test @allocated(SingleDispatch.@polymorphic func1(d, 1, 2)) == 16  # A single allocation
    run() = for _ in 1:100; SingleDispatch.@polymorphic func1(d::D1, 1, 2) end


    SingleDispatch.@extend mutable struct MutD2 <: BaseClass
        @override function func1(this::MutD2, a::Int, b::Int)::Int
            a + b
        end
    end

    const dm = MutD2()
    @test SingleDispatch.@polymorphic(func1(dm, 1, 2)) == func1(dm, 1, 2) == 3

    # NOTE: this fails in VSCode tests for some reason, but passes in the REPL.
    @test @allocated(SingleDispatch.@polymorphic func1(dm, 1, 2)) == 0
end

@testitem "Perf tests" begin
# module M
#    using Dispatch
#    using Test
    Base.Experimental.@optlevel 2  # Force optimization for tests

    SingleDispatch.@base abstract type BaseClass end
    SingleDispatch.@virtual BaseClass function vf(this::Ptr)::Int end

    SingleDispatch.@extend mutable struct D1 <: BaseClass
        x::Int
        @override function vf(this::D1)::Int
            this.x + 1
        end
    end
    SingleDispatch.@extend mutable struct D2 <: BaseClass
        x::Int
        @override function vf(this::D2)::Int
            this.x + 2
        end
    end
    # Add extra subtypes, to avoid over optimization shenanigans
    mutable struct D3 <: BaseClass x::Int end
    mutable struct D4 <: BaseClass x::Int end
    mutable struct D5 <: BaseClass x::Int end
    mutable struct D6 <: BaseClass x::Int end
    mutable struct D7 <: BaseClass x::Int end
    mutable struct D8 <: BaseClass x::Int end
    vf(d::D3) = d.x + 3
    vf(d::D4) = d.x + 3
    vf(d::D5) = d.x + 3
    vf(d::D6) = d.x + 3
    vf(d::D7) = d.x + 3
    vf(d::D8) = d.x + 3

    const ds = BaseClass[rand((D1(0), D2(0))) for _ in 1:1000]

    s1() = let out = 0
        for d in ds
            out += vf(d)
        end
        return out
    end
    s2() = let out = 0
        for d in ds
            out += SingleDispatch.@polymorphic vf(d)
        end
        return out
    end

    @test s1() == s2()

    #@test @allocated(s1()) == @allocated(s2())
    @time for _ in 1:1_000 s1() end
    @time for _ in 1:1_000 s2() end

end

# For fairest comparison w/ dynamic dispatch, don't return a value so there's no extra alloc
@testitem "Perf tests - mutable, no return value" begin
# module M2
#    using Dispatch
#    using Test
    Base.Experimental.@optlevel 2  # Force optimization for tests

    SingleDispatch.@base abstract type BaseClass end
    SingleDispatch.@virtual BaseClass function vf(this::Ptr)::Nothing end

    const out = Ref(0)

    SingleDispatch.@extend mutable struct D1 <: BaseClass
        x::Int
        @override function vf(this::D1)::Nothing
            out[] += this.x + 1
            nothing
        end
    end
    SingleDispatch.@extend mutable struct D2 <: BaseClass
        x::Int
        @override function vf(this::D2)::Nothing
            out[] += this.x + 2
            nothing
        end
    end
    # Add extra subtypes, to avoid over optimization shenanigans
    mutable struct D3 <: BaseClass x::Int end
    mutable struct D4 <: BaseClass x::Int end
    mutable struct D5 <: BaseClass x::Int end
    mutable struct D6 <: BaseClass x::Int end
    mutable struct D7 <: BaseClass x::Int end
    mutable struct D8 <: BaseClass x::Int end
    vf(::D3) = nothing
    vf(::D4) = nothing
    vf(::D5) = nothing
    vf(::D6) = nothing
    vf(::D7) = nothing
    vf(::D8) = nothing

    const ds = BaseClass[rand((D1(0), D2(0))) for _ in 1:1000]

    function s1()
        out[] = 0
        for d in ds
            vf(d)
        end
        return out[]
    end
    function s2()
        out[] = 0
        for d in ds
            SingleDispatch.@polymorphic vf(d)
        end
        return out[]
    end

    @test s1() == s2()

    #@test @allocated(s1()) == @allocated(s2())
    @time for _ in 1:1_000 s1() end
    @time for _ in 1:1_000 s2() end

end

# Another comparison: immutable objects, which will be quite poor for dynamic dispatch right now.
@testitem "Perf tests - immutable, with return value" begin
#module M3
#   using Dispatch
#   using Test
    Base.Experimental.@optlevel 2  # Force optimization for tests

    SingleDispatch.@base abstract type BaseClass end
    SingleDispatch.@virtual BaseClass function vf(this::Ptr)::Nothing end

    const out = Ref(0)

    SingleDispatch.@extend struct D1 <: BaseClass
        x::Int
        @override function vf(this::D1)::Nothing
            out[] += this.x + 1
            nothing
        end
    end
    SingleDispatch.@extend struct D2 <: BaseClass
        x::Int
        @override function vf(this::D2)::Nothing
            out[] += this.x + 2
            nothing
        end
    end
    # Add extra subtypes, to avoid over optimization shenanigans
    struct D3 <: BaseClass x::Int end
    struct D4 <: BaseClass x::Int end
    struct D5 <: BaseClass x::Int end
    struct D6 <: BaseClass x::Int end
    struct D7 <: BaseClass x::Int end
    struct D8 <: BaseClass x::Int end
    vf(::D3) = nothing
    vf(::D4) = nothing
    vf(::D5) = nothing
    vf(::D6) = nothing
    vf(::D7) = nothing
    vf(::D8) = nothing

    const ds = BaseClass[rand((D1(0), D2(0))) for _ in 1:1000]

    function s1()
        out[] = 0
        for d in ds
            vf(d)
        end
        return out[]
    end
    function s2()
        out[] = 0
        for d in ds
            SingleDispatch.@polymorphic vf(d)
        end
        return out[]
    end

    @test s1() == s2()

    #@test @allocated(s1()) == @allocated(s2())
    @time for _ in 1:1_000 s1() end
    @time for _ in 1:1_000 s2() end

end
