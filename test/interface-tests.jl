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

    e1 = @macroexpand(@interface GameObjectInterface begin
        # Returns true if the object is dead and can be deleted
        @virtual function update(::GameObjectInterface, dt::Int)::Bool end
        @virtual function render(::GameObjectInterface, renderer::TextRenderer)::Nothing end
    end)
    e2 = quote
        mutable struct GameObjectInterfaceImplementation
            update::Ptr{Cvoid}
            render::Ptr{Cvoid}
        end

        struct GameObjectInterface
            callbacks::GameObjectInterfaceImplementation
            instance::Ptr{Cvoid}
            instance_ref::Any
        end

        function update(obj_::GameObjectInterface, dt::Int)::Bool
            ccall(obj_.callbacks.update, Bool, (Int,), dt)
        end
        function render(obj_::GameObjectInterface, renderer::TextRenderer)::Nothing
            ccall(obj_.callbacks.render, Nothing, (TextRenderer,), renderer)
        end

        GameObjectInterface
    end

    @test @capture(e1, $e2)
end
