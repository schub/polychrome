defmodule Octopus.App do
  @moduledoc """
  Behaviour and functions for creating apps. An app gets started and supervised by the AppSupervisor. It can emit frames with `send_frame/1` that will be forwarded to the mixer.

  Add `use Octopus.App` to your app module to create an app. It will be added automatically to the list of availabe apps.

  An app works very similar to a GenServer and supports usual callbacks. (`init/1`, `handle_call/3`, `handle_cast/2`, `handle_info/2`, `terminate/2`).

  See `Octopus.Apps.SampleApp` for an example.

  ## App Compatibility

  Apps can implement the `compatible?/0` callback to check if they're compatible with the current installation.
  This is useful for apps that require specific panel counts, dimensions, or asset files.

  ```elixir
  def compatible?() do
    installation = Octopus.App.get_installation_info()

    # Example: App requires at least 10 panels
    installation.panel_count >= 10

    # Example: App requires one button per panel
    installation.num_buttons == installation.panel_count
  end
  ```

  If `compatible?/0` returns `false`, the app will not be started and will be visually marked as incompatible in the UI.

  ## Events
  An app can implement the `handle_event/2` callback to react to events. It will receive event structs and the genserver state.

  """

  alias Octopus.Canvas

  alias Octopus.Protobuf.{
    Frame,
    WFrame,
    RGBFrame,
    AudioFrame,
    SynthFrame
  }

  alias Octopus.Events.Event.Proximity, as: ProximityEvent
  alias Octopus.Events.Event.Audio, as: AudioEvent
  alias Octopus.Events.Event.Input, as: InputEvent
  alias Octopus.Events.Event.Lifecycle, as: LifecycleEvent

  alias Octopus.{Mixer, AppSupervisor}

  @supported_frames [Frame, RGBFrame, WFrame, AudioFrame, SynthFrame]

  @doc """
  Human readable name of the app. It will be used in the UI and other places to identify the app.
  """
  @callback name() :: binary()

  @doc """
  Optional callback to return an icon that will be used in the UI.
  """
  @callback icon() :: Canvas.t() | nil

  @doc """
  Optional callback to check if the app is compatible with the current installation.
  Returns true if the app can run, false if it's incompatible.
  Apps can check installation dimensions, panel count, or any other requirements.
  """
  @callback compatible?() :: boolean()

  @doc """
  App-specific initialization callback. This is called by the framework's init/1 function.
  Apps should implement this instead of init/1 directly.
  """
  @callback app_init(args :: any()) ::
              {:ok, state :: any()}
              | {:ok, state :: any(), timeout() | :hibernate}
              | :ignore
              | {:stop, reason :: any()}

  @doc """
  Optional callback to handle events. An app will only receive events if it is selected as active in the mixer.
  """
  @callback handle_event(
              %InputEvent{} | %AudioEvent{} | %ProximityEvent{} | %LifecycleEvent{},
              state :: any
            ) ::
              {:noreply, state :: any}

  @type config_option ::
          {String.t(), :int, %{min: integer(), max: integer(), default: integer()}}
          | {String.t(), :float, %{min: float(), max: float(), default: float()}}
          | {String.t(), :string, %{default: String.t()}}
          | {String.t(), :boolean, %{default: boolean()}}
          | {String.t(), :select, %{default: non_neg_integer(), options: list({binary(), any()})}}

  @type config_schema :: %{optional(any()) => config_option()}

  @doc """
  Returns the config schema for the app. The schema is used to generate the UI for the app interface.
  """
  @callback config_schema() :: config_schema()

  @doc """
  Returns the current config for the app. This is used to initialize the app interface UI when it is started.
  """
  @callback get_config(state :: any()) :: map()

  @doc """
  Optional callback to handle config updates. The config is updated by the UI and sent to the app via the `update_config/1` function.
  """
  @callback handle_config(config :: any(), state :: any()) :: {:noreply, state :: any()}

  defmacro __using__(opts) do
    category = Keyword.get(opts, :category, :misc)

    quote do
      @behaviour Octopus.App
      use GenServer
      import Octopus.App

      def start_link({config, init_args}) do
        GenServer.start_link(__MODULE__, config, init_args)
      end

      # Framework-provided init/1 that calls the app's app_init/1
      def init(args) do
        app_init(args)
      end

      # Default app_init/1 implementation - can be overridden by apps
      def app_init(args) do
        {:ok, %{}}
      end

      def handle_info({:event, %InputEvent{} = input_event}, state) do
        handle_event(input_event, state)
      end

      def handle_info({:event, %AudioEvent{} = audio_event}, state) do
        handle_event(audio_event, state)
      end

      def handle_info({:event, %LifecycleEvent{} = lifecycle_event}, state) do
        handle_event(lifecycle_event, state)
      end

      def handle_info({:event, %ProximityEvent{} = proximity_event}, state) do
        handle_event(proximity_event, state)
      end

      def handle_call(:get_config, _from, state) do
        {:reply, get_config(state), state}
      end

      def handle_call({:update_config, config}, _from, state) do
        app_id = AppSupervisor.lookup_app_id(self())
        {:noreply, state} = handle_config(config, state)

        {:reply, :ok, state}
      end

      def icon, do: nil

      def category(), do: unquote(category)

      def compatible?(), do: true

      def handle_event(_event, state) do
        {:noreply, state}
      end

      def handle_config(config, state) do
        {:noreply, state}
      end

      def config_schema() do
        %{}
      end

      def get_config(state) do
        %{}
      end

      defoverridable icon: 0
      defoverridable app_init: 1
      defoverridable compatible?: 0
      defoverridable handle_event: 2
      defoverridable config_schema: 0
      defoverridable handle_config: 2
      defoverridable get_config: 1
    end
  end

  def play_sample(sample_path, channel) do
    send_frame(%AudioFrame{uri: Path.join("file://", sample_path), channel: channel}, self())
  end

  @doc """
  Send a frame to the mixer.
  """
  def send_frame(%frame_type{} = frame) when frame_type in @supported_frames do
    send_frame(frame, self())
  end

  def send_frame(%frame_type{} = frame, pid) when frame_type in @supported_frames do
    app_id = AppSupervisor.lookup_app_id(pid)
    Mixer.handle_frame(app_id, frame)
  end

  def send_canvas(%Canvas{} = canvas) do
    app_id = AppSupervisor.lookup_app_id(self())
    Mixer.handle_canvas(app_id, canvas)
  end

  @spec default_config(config_schema()) :: map
  def default_config(config_schema) do
    config_schema
    |> Enum.map(fn
      {key, {_name, :select, %{default: default, options: options}}} ->
        {_name, value} = Enum.at(options, default)
        {key, value}

      {key, {_name, _type, options}} ->
        {key, Map.fetch!(options, :default)}
    end)
    |> Map.new()
  end

  def get_app_id() do
    AppSupervisor.lookup_app_id(self())
  end

  def get_screen_count() do
    Application.get_env(:octopus, :installation).screens()
  end

  @doc """
  Returns installation information for compatibility checking.
  Apps can use this in their compatible?/0 callback to check panel count,
  dimensions, or other installation-specific requirements.
  """
  def get_installation_info() do
    installation = Application.get_env(:octopus, :installation)

    %{
      panel_count: installation.panel_count(),
      panel_width: installation.panel_width(),
      panel_height: installation.panel_height(),
      panel_gap: installation.panel_gap(),
      width: installation.width(),
      height: installation.height(),
      num_buttons: installation.num_buttons()
    }
  end

  # New unified Display API (Phase 1)

  @doc """
  Configures display buffers for the current app.

  Options:
  - `:layout` - Layout type (:gapped_panels, :adjacent_panels). Default: :gapped_panels
  - `:supports_rgb` - Whether app will use RGB buffers. Default: true
  - `:supports_grayscale` - Whether app will use grayscale buffers. Default: false
  - `:default_transparency` - Default transparency value. Default: 1.0
  - `:easing_interval` - Hardware transition smoothness in milliseconds. Default: 0 (instant)
  """
  def configure_display(opts \\ []) do
    # Require explicit layout specification - no defaults
    layout = Keyword.fetch!(opts, :layout)

    config = %{
      layout: layout,
      supports_rgb: Keyword.get(opts, :supports_rgb, true),
      supports_grayscale: Keyword.get(opts, :supports_grayscale, false),
      default_transparency: Keyword.get(opts, :transparency, 1.0),
      easing_interval: Keyword.get(opts, :easing_interval, 0)
    }

    # Creates buffers in mixer immediately
    Mixer.create_display_buffers(get_app_id(), config)
  end

  @doc """
  Returns display information for the current installation.

  Replaces VirtualMatrix and direct installation access with a unified interface.

  Returns:
  %{
    width: integer(),          # Total display width
    height: integer(),         # Total display height
    panel_width: integer(),    # Width of each panel
    panel_height: integer(),   # Height of each panel
    panel_count: integer(),    # Number of panels
    panel_gap: integer(),      # Gap between panels
    panel_range: function(),   # fn(panel_id, :x | :y) -> {start, end}
    panel_at_coord: function() # fn(x, y) -> panel_id | :not_found
  }
  """
  def get_display_info() do
    # Get app-specific display info based on the app's layout configuration
    app_id = get_app_id()

    case Mixer.get_app_display_info(app_id) do
      nil ->
        # Fallback to global display info for backward compatibility
        Mixer.get_display_info()

      display_info ->
        display_info
    end
  end

  @doc """
  Gets display information for a specific app (used internally).
  """
  def get_app_display_info(app_id) do
    Mixer.get_app_display_info(app_id)
  end

  @doc """
  Updates the display with new canvas data.

  Replaces send_frame() and send_canvas() with unified buffer updates.

  Args:
  - canvas: Canvas to display
  - mode: :rgb | :grayscale (default: :rgb)
  - easing_interval: Hardware transition smoothness in milliseconds (optional, uses app default if not provided)
  """
  def update_display(canvas, mode \\ :rgb, opts \\ []) do
    app_id = get_app_id()
    easing_interval = Keyword.get(opts, :easing_interval, nil)
    Mixer.update_app_display(app_id, canvas, mode, easing_interval)
  end
end
