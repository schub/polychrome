defmodule Octopus.Apps.TenLetters do
  use Octopus.App, category: :animation, output_type: :grayscale
  use Octopus.Params, prefix: :tla

  alias Octopus.Font
  alias Octopus.Transitions
  alias Octopus.Canvas
  alias Octopus.Animator

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
        case lookup[current_word_index] do
          nil ->
            # Current word not found in lookup (e.g., spaces), return empty list to trigger random selection
            []

          candidates ->
            candidates
            |> Stream.map(&Enum.at(words, &1))
            |> Stream.reject(fn word -> word in exclude end)
            |> Enum.take(1)
        end

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

  def icon(), do: Canvas.from_string("T", Font.load("BlinkenLightsRegular"), 3)

  def app_init(_) do
    # Configure display for grayscale output using modern unified API
    Octopus.App.configure_display(
      layout: :adjacent_panels,
      supports_rgb: false,
      supports_grayscale: true,
      easing_interval: 150
    )

    # Get display info for dynamic sizing
    display_info = Octopus.App.get_display_info()

    path = Path.join([:code.priv_dir(:octopus), "words", "nog24-256-10--letter-words.txt"])
    words = Words.load(path)
    :timer.send_after(0, :next_word)

    # Start with a "blank word" (10 spaces) - this allows normal transition logic to handle the first word
    # 10 spaces
    current_word = "          "
    font = Font.load("BlinkenLightsRegular")
    font_variants_count = length(font.variants)

    # Initialize with a blank display
    blank_canvas = Canvas.new(display_info.width, display_info.height)
    grayscale_canvas = Canvas.to_grayscale(blank_canvas)
    Octopus.App.update_display(grayscale_canvas, :grayscale, easing_interval: 150)

    {:ok,
     %{
       words: words,
       last_words: [],
       font: font,
       font_variants_count: font_variants_count,
       current_word: current_word,
       display_info: display_info,
       # Track individual letter canvases - start empty
       letter_canvases: %{}
     }}
  end

  defp random_transition_for_index(i) do
    case i do
      0 ->
        &Transitions.push(&1, &2, direction: :right, separation: 3)

      9 ->
        &Transitions.push(&1, &2, direction: :left, separation: 3)

      _ ->
        if :rand.uniform() > 0.5 do
          &Transitions.push(&1, &2, direction: :top, separation: 3)
        else
          &Transitions.push(&1, &2, direction: :bottom, separation: 3)
        end
    end
  end

  def handle_info(
        :next_word,
        %{
          words: words,
          current_word: current_word,
          last_words: last_words,
          font: _font,
          display_info: display_info
        } = state
      ) do
    last_words = [current_word | last_words] |> Enum.take(param(:last_word_list_size, 250))
    next_word = Words.next(words, current_word, last_words)

    Logger.debug("Next Word: #{next_word}")

    # Simple logic: only animate letters that changed
    # For the first word, all letters change from space to letter, so all animate automatically
    String.split(state.current_word, "", trim: true)
    |> Enum.zip(String.split(next_word, "", trim: true))
    |> Enum.with_index()
    |> Enum.each(fn
      {{a, a}, _} ->
        nil

      {{_, b}, i} ->
        # Use dynamic panel width instead of hardcoded 8
        panel_width = display_info.panel_width

        canvas =
          Canvas.new(panel_width, display_info.height)
          |> Canvas.put_string({0, 0}, b, state.font)

        :timer.send_after(
          :rand.uniform(param(:max_letter_delay, 1000)),
          {:animate_letter, i, canvas}
        )
    end)

    :timer.send_after(param(:word_duration, 5000), :next_word)
    {:noreply, %{state | last_words: last_words, current_word: next_word}}
  end

  def handle_info({:animator_update, animation_id, canvas, frame_status}, state) do
    # Handle canvas updates from the Animator module with animation identification
    updated_state =
      case animation_id do
        {:letter, letter_index} ->
          # Update the specific letter canvas
          update_letter_canvas(state, letter_index, canvas, frame_status)

        _ ->
          # For other animations, convert to grayscale and update display
          grayscale_canvas = Canvas.to_grayscale(canvas)

          Octopus.App.update_display(grayscale_canvas, :grayscale, easing_interval: 150)

          state
      end

    {:noreply, updated_state}
  end

  def handle_info({:animate_letter, i, target_canvas}, %{display_info: display_info} = state) do
    transition = random_transition_for_index(i)

    # Check if we have any existing letter canvas for this position
    existing_letter_canvas = Map.get(state.letter_canvases, i)

    current_canvas =
      if existing_letter_canvas do
        # Use the existing animated letter canvas
        existing_letter_canvas
      else
        # For positions without existing letters, start from blank (which represents spaces)
        Canvas.new(display_info.panel_width, display_info.height)
      end

    # Create a transition function that uses the current state as the starting point
    transition_with_current = fn _blank_canvas, to_canvas ->
      # Ignore the blank canvas from Animator and use our current state canvas
      transition.(current_canvas, to_canvas)
    end

    # Use new single-call API for letter animation
    Animator.animate(
      animation_id: {:letter, i},
      app_pid: self(),
      canvas: target_canvas,
      position: {0, 0},
      transition_fun: transition_with_current,
      duration: 1500,
      canvas_size: {display_info.panel_width, display_info.height},
      frame_rate: 30
    )

    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.warning("Unexpected message in Ten Letters: #{inspect(msg)}")
    {:noreply, state}
  end

  defp update_letter_canvas(state, letter_index, canvas, frame_status) do
    # Get current letter canvases
    letter_canvases = Map.get(state, :letter_canvases, %{})
    updated_letter_canvases = Map.put(letter_canvases, letter_index, canvas)

    # Start with a blank canvas and only show animated letters
    # This prevents conflicts between background word and animated letters
    background_canvas = Canvas.new(state.display_info.width, state.display_info.height)

    # Overlay animated letters on the blank background
    new_display_canvas =
      Enum.reduce(updated_letter_canvases, background_canvas, fn {letter_idx, letter_canvas},
                                                                 acc ->
        x_offset = letter_idx * state.display_info.panel_width
        Canvas.overlay(acc, letter_canvas, offset: {x_offset, 0})
      end)

    # Convert to grayscale and update display
    grayscale_canvas = Canvas.to_grayscale(new_display_canvas)

    # Only update display for efficiency (could optimize further to only update on :final)
    Octopus.App.update_display(grayscale_canvas, :grayscale, easing_interval: 150)

    # Update state with new letter canvases
    Map.put(state, :letter_canvases, updated_letter_canvases)
  end
end
