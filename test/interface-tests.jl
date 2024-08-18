@testitem "interface / implementation e2e example" begin
    struct TextRenderer
        buffer::Vector{UInt8}
    end
    TextRenderer(s::AbstractString) = TextRenderer(codeunits(s))
    function render_char(renderer::TextRenderer, x::Int, c::UInt8)::Nothing
        if x < 1 || x > length(renderer.buffer)
            return nothing
        end
        renderer.buffer[x] = c
        return nothing
    end

    @interface GameObjectInterface begin
        # Returns true if the object is dead and can be deleted
        @virtual function update(::GameObjectInterface, dt::Float64)::Bool end
        @virtual function render(::GameObjectInterface, renderer::TextRenderer)::Nothing end
    end

    @implement {GameObjectInterface} mutable struct Mushroom
        x::Float64
        vel::Float64  # pixels per second
        dead::Bool  # once it's eaten

        @override function update(p::Mushroom, dt::Float64)::Bool
            p.x += p.vel * dt
            if p.dead
                return true
            end
            return false
        end
        @override function render(p::Mushroom, renderer::TextRenderer)::Nothing
            render_char(renderer, Int(round(p.x)), UInt8('m'))
            return nothing
        end
    end

    @implement {GameObjectInterface} mutable struct Player
        x::Float64
        vel::Float64  # pixels per second
        big::Bool
        mushroom_ref::Union{Nothing, Mushroom}

        @override function update(p::Player, dt::Float64)::Bool
            p.x += p.vel * dt
            if p.mushroom_ref !== nothing
                if Int(round(p.x)) == Int(round(p.mushroom_ref.x))
                    # Eat the mushroom
                    p.big = true
                    p.mushroom_ref.dead = true
                    p.mushroom_ref = nothing
                end
            end
            return false
        end
        @override function render(p::Player, renderer::TextRenderer)::Nothing
            if p.big
                render_char(renderer, Int(round(p.x)), UInt8('P'))
            else
                render_char(renderer, Int(round(p.x)), UInt8('p'))
            end
            return nothing
        end
    end


    struct Game
        objects::Vector{GameObjectInterface}
        renderer::TextRenderer
    end
    function Game()
        m = Mushroom(6.0, -0.25, false)
        p = Player(0.0, 1.0, false, m)
        r = TextRenderer("")
        return Game(GameObjectInterface[p, m], r)
    end
    function game_loop()
        g = Game()
        empty = "------------------------------"
        append!(g.renderer.buffer, codeunits(empty))
        gamestates = []
        for _ in 1:10
            todelete = Int[]
            for (i,obj) in enumerate(g.objects)
                should_delete = update(obj, 1.0)
                should_delete && push!(todelete, i)
            end
            deleteat!(g.objects, todelete)

            g.renderer.buffer .= codeunits(empty)
            for obj in g.objects
                render(obj, g.renderer)
            end

            push!(gamestates, String(copy(g.renderer.buffer)))
        end
        gamestates
    end
    @test game_loop() == [
        "p----m------------------------"
        "-p---m------------------------"
        "--p-m-------------------------"
        "---pm-------------------------"
        "----P-------------------------"
        "-----P------------------------"
        "------P-----------------------"
        "-------P----------------------"
        "--------P---------------------"
        "---------P--------------------"
    ]
end

@testitem "interface macroexpand" begin
    using MacroTools

    e1 = @macroexpand(
        @interface GameObjectInterface begin
            # Returns true if the object is dead and can be deleted
            @virtual function update(::GameObjectInterface, dt::Int)::Bool end
            @virtual function render(::GameObjectInterface, renderer::TextRenderer)::Nothing end
        end
    )
    e2 = quote
        mutable struct GameObjectInterfaceImplementation
            update::Ptr{Cvoid}
            render::Ptr{Cvoid}
        end
        # TODO: Add this
        # # For type-checking implementations
        # const GameObjectInterfaceTypes = Set([
        #     (update, Bool, (Ptr{Cvoid},Int)),
        #     (render, Bool, (Ptr{Cvoid},TextRenderer)),
        # ])

        struct GameObjectInterface
            callbacks::GameObjectInterfaceImplementation
            instance::Ptr{Cvoid}
            instance_ref::Any
        end

        function update(obj_::GameObjectInterface, dt::Int)::Bool
            ccall(obj_.callbacks.update, Bool, (Ptr{Cvoid}, Int,), obj_.instance, dt)
        end
        function render(obj_::GameObjectInterface, renderer::TextRenderer)::Nothing
            ccall(obj_.callbacks.render, Nothing, (Ptr{Cvoid}, TextRenderer,), obj_.instance, renderer)
        end

        GameObjectInterface
    end

    @test @capture(e1, $e2)
end

@testitem "implement macroexpand - mutable" begin
    using MacroTools

    e1 = @macroexpand(
        @implement {GameObjectInterface} mutable struct Goomba
            health::Int
            @override function update(this::Goomba, dt::Int)::Bool
                print("Goomba update: ", this.health, " ", dt)
                return false
            end
            @override function render(this::Goomba, renderer::TextRenderer)::Nothing
                print("Goomba update: ", this.health)
            end
        end
    )
    e2 = Base.remove_linenums!(quote
        mutable struct Goomba
            health::Int
        end
        function update(this::Goomba, dt::Int)::Bool
            print("Goomba update: ", this.health, " ", dt)
            return false
        end
        function render(this::Goomba, renderer::TextRenderer)::Nothing
            print("Goomba update: ", this.health)
        end

        function Goomba_GameObjectInterface_impl__update(instance::Ptr{Cvoid}, dt::Int)
            obj_ = unsafe_pointer_to_objref(reinterpret(Ptr{Goomba}, instance))::Goomba
            # TODO: These @inlines prevent @capture from matching. Need to expand them here.
            return @inline update(obj_, dt)
        end
        function Goomba_GameObjectInterface_impl__render(instance::Ptr{Cvoid}, renderer::TextRenderer)
            obj_ = unsafe_pointer_to_objref(reinterpret(Ptr{Goomba}, instance))::Goomba
            return @inline render(obj_, renderer)
        end

        const GoombaGameObjectInterfaceImplementation = eval(:(GameObjectInterfaceImplementation(
            @cfunction(Goomba_GameObjectInterface_impl__update, Bool, (Ptr{Cvoid},Int)),
            @cfunction(Goomba_GameObjectInterface_impl__render, Nothing, (Ptr{Cvoid},TextRenderer)),
        )))

        function Base.convert(::Type{GameObjectInterface}, obj::Goomba)::GameObjectInterface
            GameObjectInterface(GoombaGameObjectInterfaceImplementation, pointer_from_objref(obj), obj)
        end

        Goomba
    end)

    # TODO: It's not possible to get these to match, due to the `@inline` and `eval`
    # @test @capture(e1, $e2)
end

