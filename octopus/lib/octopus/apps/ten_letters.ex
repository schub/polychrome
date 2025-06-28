defmodule Octopus.Apps.TenLetters do
  use Octopus.App, category: :animation, output_type: :grayscale
  use Octopus.Params, prefix: :tla

  alias Octopus.Font
  alias Octopus.Canvas
  alias Octopus.TimeAnimator

  require Logger

  defmodule Words do
    defstruct [:words, :lookup]

    def load(path) do
      words =
        path
        |> File.read!()
        |> String.split("\n", trim: true)
        |> Enum.filter(fn word -> String.length(word) == 10 end)
        |> Enum.shuffle()
        |> Enum.map(&String.upcase/1)
        |> Enum.with_index()

      lookup =
        words
        |> Stream.map(fn {word_1, index_1} ->
          new_candidates =
            words
            |> Enum.reduce([], fn {word_2, index_2}, candidates ->
              if index_1 == index_2 do
                candidates
              else
                [{index_2, distance(word_1, word_2)} | candidates]
              end
            end)
            |> Enum.sort_by(&elem(&1, 1))
            |> Enum.map(&elem(&1, 0))

          new_candidates =
            if length(new_candidates) > 30 do
              Enum.drop(new_candidates, 20)
            else
              new_candidates
            end
            |> Enum.take(10)

          {index_1, new_candidates}
        end)
        |> Enum.into(%{})

      %__MODULE__{words: words |> Enum.to_list() |> Enum.map(&elem(&1, 0)), lookup: lookup}
    end

    def next(%__MODULE__{words: words, lookup: lookup}, current_word, exclude \\ []) do
      current_word_index = Enum.find_index(words, &(&1 == current_word))

      candidate =
        lookup[current_word_index]
        |> Stream.map(&Enum.at(words, &1))
        |> Stream.reject(fn word -> word in exclude end)
        |> Enum.take(1)

      case candidate do
        [] -> Enum.random(words)
        [word | _] -> word
      end
    end

    # computes the levenshtein distance between two strings
    defp distance(a, b) do
      do_distance(a |> String.graphemes(), b |> String.graphemes(), 0)
    end

    defp do_distance([], [], distance), do: distance

    defp do_distance([a | rest_a], [b | rest_b], distance) do
      if a == b do
        do_distance(rest_a, rest_b, distance)
      else
        do_distance(rest_a, rest_b, distance + 1)
      end
    end
  end

  def name, do: "Ten Letters"

  def app_init(_) do
    # Configure display for grayscale output
    Octopus.App.configure_display(
      layout: :adjacent_panels,
      supports_rgb: false,
      supports_grayscale: true,
      easing_interval: 150
    )

    path = Path.join([:code.priv_dir(:octopus), "words", "nog24-256-10--letter-words.txt"])
    words = Words.load(path)
    :timer.send_after(0, :next_word)

    current_word = Enum.random(words.words)
    font = Font.load("BlinkenLightsRegular")

    # Create initial canvas and display it
    display_info = Octopus.App.get_display_info()

    current_canvas =
      Canvas.new(display_info.width, display_info.height, :rgb)
      |> Canvas.put_string({0, 0}, current_word, font)
      |> Canvas.to_grayscale()

    Octopus.App.update_display(current_canvas, :grayscale)

    # Start animation timer (30 FPS for smooth animations)
    :timer.send_interval(33, :animate_frame)

    {:ok,
     %{
       words: words,
       last_words: [],
       font: font,
       current_word: current_word,
       current_canvas: current_canvas,
       next_word: nil,
       # Track ongoing letter animations
       letter_animations: %{},
       frame_counter: 0
     }}
  end

  def handle_info(
        :next_word,
        %{
          words: words,
          current_word: current_word,
          last_words: last_words,
          font: font
        } = state
      ) do
    last_words = [current_word | last_words] |> Enum.take(param(:last_word_list_size, 250))
    next_word = Words.next(words, current_word, last_words)

    Logger.debug("Next Word: #{next_word}")

    # Start letter animations for changed letters
    new_animations =
      String.split(current_word, "", trim: true)
      |> Enum.zip(String.split(next_word, "", trim: true))
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn
        {{a, a}, _}, acc ->
          # Letter didn't change, no animation needed
          acc

        {{old_letter, new_letter}, i}, acc ->
          # Letter changed, start animation after random delay
          delay_ms = :rand.uniform(param(:max_letter_delay, 1000))
          start_time = System.monotonic_time(:millisecond) + delay_ms

          # Create source canvas for this letter (what it currently looks like)
          source_canvas =
            Canvas.new(8, 8, :rgb)
            |> Canvas.put_string({0, 0}, old_letter, font)
            |> Canvas.to_grayscale()

          # Create target canvas for this letter (what it should become)
          target_canvas =
            Canvas.new(8, 8, :rgb)
            |> Canvas.put_string({0, 0}, new_letter, font)
            |> Canvas.to_grayscale()

          # Choose transition direction based on position
          transition_direction =
            case i do
              0 -> :right
              9 -> :left
              _ -> if :rand.uniform() > 0.5, do: :top, else: :bottom
            end

          Map.put(acc, i, %{
            source_canvas: source_canvas,
            target_canvas: target_canvas,
            start_time: start_time,
            # 1.5 seconds
            duration: 1500,
            direction: transition_direction
          })
      end)

    # Merge new animations with existing ones
    updated_animations = Map.merge(state.letter_animations, new_animations)

    :timer.send_after(param(:word_duration, 5000), :next_word)

    {:noreply,
     %{
       state
       | last_words: last_words,
         next_word: next_word,
         letter_animations: updated_animations
     }}
  end

  def handle_info(:animate_frame, state) do
    current_time = System.monotonic_time(:millisecond)
    display_info = Octopus.App.get_display_info()

    # Start with base canvas
    result_canvas = Canvas.new(display_info.width, display_info.height, :grayscale)

    # Split animations into active, pending, and finished
    {active_animations, other_animations} =
      Enum.split_with(state.letter_animations, fn {_pos, animation} ->
        current_time >= animation.start_time and
          current_time < animation.start_time + animation.duration
      end)

    {pending_animations, finished_animations} =
      Enum.split_with(other_animations, fn {_pos, animation} ->
        current_time < animation.start_time
      end)

    # Render each letter position
    result_canvas =
      0..9
      |> Enum.reduce(result_canvas, fn position, canvas_acc ->
        letter_x = position * 8

        cond do
          # Check if this position has an active animation
          active_animation = Enum.find(active_animations, fn {pos, _} -> pos == position end) ->
            {_, animation} = active_animation
            elapsed = current_time - animation.start_time
            time_progress = min(1.0, elapsed / animation.duration)

            # Evaluate transition at current time
            animated_canvas =
              TimeAnimator.evaluate_transition(
                animation.source_canvas,
                animation.target_canvas,
                time_progress,
                :push,
                direction: animation.direction
              )

            # Place animated letter into result canvas
            Canvas.overlay(canvas_acc, animated_canvas, offset: {letter_x, 0})

          # Check if this position has a pending animation (show source)
          pending_animation = Enum.find(pending_animations, fn {pos, _} -> pos == position end) ->
            {_, animation} = pending_animation
            Canvas.overlay(canvas_acc, animation.source_canvas, offset: {letter_x, 0})

          # Check if this position has a finished animation (show target)
          finished_animation = Enum.find(finished_animations, fn {pos, _} -> pos == position end) ->
            {_, animation} = finished_animation
            Canvas.overlay(canvas_acc, animation.target_canvas, offset: {letter_x, 0})

          # No animation for this position, get letter from current canvas
          true ->
            # Extract the letter at this position from current canvas
            letter_canvas = extract_letter_canvas(state.current_canvas, position)
            Canvas.overlay(canvas_acc, letter_canvas, offset: {letter_x, 0})
        end
      end)

    # Update display
    Octopus.App.update_display(result_canvas, :grayscale)

    # Update current canvas and word when all animations finish
    {updated_current_canvas, updated_current_word} =
      if Enum.empty?(active_animations) and Enum.empty?(pending_animations) and
           Map.get(state, :next_word) do
        # All animations are done, update to the new word
        new_canvas =
          Canvas.new(display_info.width, display_info.height, :rgb)
          |> Canvas.put_string({0, 0}, state.next_word, state.font)
          |> Canvas.to_grayscale()

        {new_canvas, state.next_word}
      else
        {state.current_canvas, state.current_word}
      end

    # Remove finished animations
    remaining_animations =
      (active_animations ++ pending_animations)
      |> Map.new()

    {:noreply,
     %{
       state
       | letter_animations: remaining_animations,
         current_canvas: updated_current_canvas,
         current_word: updated_current_word,
         next_word:
           if(updated_current_word == Map.get(state, :next_word),
             do: nil,
             else: Map.get(state, :next_word)
           ),
         frame_counter: state.frame_counter + 1
     }}
  end

  # Helper function to extract an 8x8 letter canvas from the full canvas
  defp extract_letter_canvas(canvas, position) do
    letter_x = position * 8

    # Create a new 8x8 canvas
    letter_canvas = Canvas.new(8, 8, :grayscale)

    # Copy pixels from the source canvas
    pixels =
      for x <- 0..7, y <- 0..7, into: %{} do
        source_pixel = Canvas.get_pixel(canvas, {letter_x + x, y})
        {{x, y}, source_pixel}
      end

    %{letter_canvas | pixels: pixels}
  end
end
