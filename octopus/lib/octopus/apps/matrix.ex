defmodule Octopus.Apps.Matrix do
  use Octopus.App, category: :animation
  use Octopus.Params, prefix: :matrix

  defmodule Particle do
    defstruct [:x, :y, :z, :speed, :color, :age, :max_age, :tail]
  end

  defmodule State do
    @greens [{164, 223, 179}, {86, 115, 70}, {44, 64, 11}, {22, 40, 0}]
    @pinks [{251, 72, 196}, {165, 52, 167}, {77, 40, 92}]

    alias Octopus.Canvas

    defstruct [:canvas, :particles, :width, :height]

    def spawn_particles(
          %State{particles: particles, width: width, height: height} = state,
          amount
        ) do
      new_particles =
        Enum.map(1..amount, fn _ ->
          speed =
            if :rand.uniform() > 0.9 do
              18.0
            else
              3.0 + :rand.uniform() * 12.0
            end

          %Particle{
            x: :rand.uniform(width),
            y: :rand.uniform(height) - 12,
            z: :rand.uniform() * 0.5 + 0.5,
            speed: speed,
            age: 0.0,
            max_age: 5 + :rand.uniform() * 6,
            tail: Enum.map(1..(4 + :rand.uniform(3)), fn _ -> Enum.random(@greens) end),
            color: {:rand.uniform(40), 200 + :rand.uniform(55), :rand.uniform(40)}
          }
        end)

      %State{state | particles: particles ++ new_particles}
    end

    def update(state, dt) do
      particles =
        state.particles
        |> Enum.map(fn %Particle{x: x, y: y, speed: speed, age: age} = particle ->
          %Particle{
            particle
            | x: x,
              y: y + speed * dt,
              speed: speed,
              age: age + dt
          }
        end)
        |> Enum.filter(fn %Particle{y: y, age: age, max_age: max_age} ->
          y < state.height * 2 and age < max_age
        end)

      %State{state | particles: particles}
    end

    def render(%State{particles: particles, width: width, height: height} = state) do
      canvas = Canvas.new(width, height)

      canvas =
        particles
        |> Enum.sort_by(fn %Particle{z: z} -> z end)
        |> Enum.reduce(canvas, fn %Particle{x: x, y: y, age: _age} = particle, canvas ->
          canvas =
            particle.tail
            |> Enum.with_index()
            |> Enum.reduce(canvas, fn {color, i}, c ->
              Canvas.put_pixel(c, {trunc(x), trunc(y - i - 1)}, color)
            end)

          Canvas.put_pixel(canvas, {trunc(x), trunc(y)}, {150, 255, 150})
        end)

      %State{state | canvas: canvas}
    end

    def change_colors(%State{particles: particles} = state) do
      particles =
        particles
        |> Enum.map(fn %Particle{tail: tail} = particle ->
          tail =
            Enum.map(tail, fn color ->
              rand = :rand.uniform()

              cond do
                rand > 0.99 and color not in @pinks ->
                  if :rand.uniform() > 0.4, do: List.first(@greens), else: {0, 0, 0}

                rand > 0.9 and color not in @pinks ->
                  @greens |> Enum.drop(1) |> Enum.random()

                true ->
                  color
              end
            end)

          %Particle{particle | tail: tail}
        end)

      %State{state | particles: particles}
    end
  end

  alias Octopus.Canvas

  def name(), do: "Matrix"

  def app_init(_args) do
    # Configure display using new unified API - adjacent layout (was Canvas.to_frame())
    Octopus.App.configure_display(layout: :adjacent_panels)

    # This is for the 10 panel installation that Matrix was made for

    # Get dimensions from display info instead of installation
    display_info = Octopus.App.get_display_info()
    width = display_info.width
    height = display_info.height

    canvas = Canvas.new(width, height)
    particles = []
    :timer.send_interval(trunc(1000 / 60), :tick)
    :timer.send_interval(50, :spawn_particles)
    :timer.send_interval(50, :change_colors)
    {:ok, %State{canvas: canvas, particles: particles, width: width, height: height}}
  end

  def handle_info(:change_colors, %State{} = state) do
    {:noreply, State.change_colors(state)}
  end

  def handle_info(:spawn_particles, %State{} = state) do
    state =
      if Enum.count(state.particles) < 200 do
        State.spawn_particles(state, 3)
      else
        state
      end

    {:noreply, state}
  end

  def handle_info(:tick, %State{} = state) do
    state = state |> State.update(1 / 60 * param(:speed, 1.0)) |> State.render()
    # Use new unified display API instead of Canvas.to_frame() |> send_frame()
    Octopus.App.update_display(state.canvas)
    {:noreply, state}
  end
end
