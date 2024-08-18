@testitem "interface / implementation e2e example" begin
    struct TextRenderer
        buffer::Vector{UInt8}
    end
    TextRenderer(s) = TextRenderer(codeunits(s))
    function render_char(renderer::Renderer, x::Int, c::UInt8)::Nothing
        if x < 1 || x > length(renderer.buffer)
            return nothing
        end
        renderer.buffer[x] = c
        return nothing
    end

    @interface GameObjectInterface begin
        # Returns true if the object is dead and can be deleted
        @virtual function update(::GameObjectInterface, dt::Int)::Bool end
        @virtual function render(::GameObjectInterface, renderer)::Nothing end
    end

    @implement GameObjectInterface mutable struct Player
        x::Float64
        vel::Float64  # pixels per second
        big::Bool
        mushroom_ref::Union{Nothing, Mushroom}

        @override function update(p::Player, dt::Int)::Bool
            p.x += p.vel * dt
            if p.mushroom_ref !== nothing && p.x == p.mushroom_ref.x
                # Eat the mushroom
                p.big = true
                p.mushroom_ref = nothing
                p.mushroom_ref.dead = true
            end
            return false
        end
        @override function render(p::Player, renderer::Renderer)::Nothing
            if p.big
                render_dot(renderer, p.x, UInt8('P'))
            else
                render_dot(renderer, p.x, UInt8('p'))
            end
            return nothing
        end
    end

    @implement GameObjectInterface mutable struct Mushroom
        x::Float64
        vel::Float64  # pixels per second
        dead::Bool  # once it's eaten

        @override function update(p::Mushroom, dt::Int)::Bool
            p.x += p.vel * dt
            if p.dead
                return true
            end
            return false
        end
        @override function render(p::Mushroom, renderer::Renderer)::Nothing
            render_dot(renderer, p.x, UInt8('m'))
            return nothing
        end
    end


    struct Game
        objects::Vector{GameObjectInterface}
        renderer::Renderer
    end
    function Game()
        m = Mushroom(10.0, -2.0, false)
        p = Player(0.0, 5.0, false, m)
        r = TextRenderer("--------------------------------")
        return Game(GameObjectInterface[p, m], r)
    end
    function game_loop()
        g = Game()
        for _ in 1:10
            todelete = Int[]
            for (i,obj) in enumerate(g.objects)
                should_delete = update(obj, 1.0)
                should_delete && push!(todelete, i)
            end
            deleteat!(g.objects, todelete)

            for obj in g.objects
                render(obj, g.renderer)
            end

            println(String(copy(g.renderer.buffer)))
        end
    end

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
            return @inline update(obj_, dt)
        end
        function Goomba_GameObjectInterface_impl__render(instance::Ptr{Cvoid}, renderer::TextRenderer)
            obj_ = unsafe_pointer_to_objref(reinterpret(Ptr{Goomba}, instance))::Goomba
            return @inline render(obj_, renderer)
        end

        const GoombaGameObjectInterfaceImplementation = eval(:(GameObjectInterfaceImplementation(
            @cfunction(update, Bool, (Ptr{Cvoid},Int)),
            @cfunction(render, Bool, (Ptr{Cvoid},TextRenderer)),
        )))

        function Base.convert(::Type{GameObjectInterface}, obj::Goomba)::GameObjectInterface
            GameObjectInterface(GoombaGameObjectInterfaceImplementation, pointer_from_objref(obj), obj)
        end

        Goomba
    end)

    # TODO: It's not possible to get these to match, due to the `@inline` and `eval`
    #@test @capture(e1, $e2)
end

