# Octopus Display System Refactoring Plan

## Motivation

The current Octopus display system has several architectural issues that limit its flexibility and scalability:

### Current Problems
1. **Tight Coupling**: Apps are tightly coupled to network-level frame sending via `send_frame()` and `send_canvas()`
2. **No App Isolation**: Apps lack proper abstraction from the underlying panel hardware and network protocols
3. **Single App Limitation**: Only one app can display content at a time, preventing visual mixing and composition
4. **Complex Dependencies**: Apps must understand `VirtualMatrix`, installation modules, and frame generation details
5. **No Transparency Support**: Cannot blend multiple apps or apply visual effects like transparency
6. **Inconsistent Patterns**: Multiple different approaches for accessing display information (VirtualMatrix, direct installation access, Canvas.to_frame())

### Goals
1. **Decouple Apps from Frame Sending**: Replace direct frame sending with a "display update" abstraction
2. **Centralized Display Buffers**: Store app-specific buffers in the mixer, not in app processes
3. **Multi-App Visual Mixing**: Allow multiple apps to render simultaneously with configurable transparency
4. **Unified Display API**: Single, clean API for all display operations replacing VirtualMatrix and installation access
5. **RGB + Grayscale Support**: Support both color modes with proper mixing capabilities
6. **Flexible Output Modes**: Support RGB-only, grayscale-only, and masked (grayscale as alpha) output modes

## Architecture Overview

### New Components
- **Enhanced Mixer**: Centralized display buffer management and visual mixing engine
- **Unified Display API**: Single `Octopus.App.get_display_info()` and `update_display()` interface
- **App Display Buffers**: Per-app RGB and grayscale buffers stored in mixer state
- **Visual Mixing Engine**: Blends multiple app buffers with transparency and effects

### Eliminated Components
- **VirtualMatrix.ex**: All functionality absorbed into mixer display management
- **Direct Installation Access**: Apps no longer need `defdelegate installation, to: Octopus`
- **Canvas.to_frame()**: Replaced with display buffer updates

## Phase 1: Core Display System Foundation

### 1.1 Enhanced Mixer Architecture
```elixir
defmodule Octopus.Mixer do
  defmodule State do
    defstruct [
      # App display buffers (replaces VirtualMatrix functionality)
      app_displays: %{},  # %{app_id => %{rgb_buffer: canvas, grayscale_buffer: canvas, config: %{}}}
      
      # Current rendering state
      selected_apps: [],  # List of app_ids to include in mixdown
      output_mode: :rgb,  # :rgb | :grayscale | :masked
      
      # Installation info (cached for performance)
      display_info: %{
        width: 272, height: 8, panel_width: 8, panel_height: 8,
        panel_count: 12, panel_gap: 16, panels: [...],
        panel_range: fn(...), panel_at_coord: fn(...)
      },
      
      # Existing transition system (adapted for multi-app)
      transition: nil,  # {:out, time_left} | {:in, time_left} | nil
      max_luminance: 255
    ]
  end
end
```

#### Transition System Adaptation
The existing luminance-based transition system works seamlessly with multi-app mixing:

```elixir
# Current: Single app transitions
case selected_app do
  {_, _} -> no_transition()     # Dual apps
  _ -> start_transition()       # Single apps  
end

# New: Multi-app transition support
case get_selected_apps() do
  [_single] -> start_transition()      # Single app gets transitions
  [_multiple | _] -> no_transition()   # Multiple apps render immediately
end

# Transition application works with mixed content
defp apply_transition_luminance(mixed_frame, transition_state) do
  case transition_state do
    {:out, time} -> 
      luminance = Easing.cubic_in(time / @transition_duration) * max_luminance
      Broadcaster.set_luminance(trunc(luminance))
    {:in, time} ->
      luminance = (1 - Easing.cubic_out(time / @transition_duration)) * max_luminance  
      Broadcaster.set_luminance(trunc(luminance))
    nil -> 
      Broadcaster.set_luminance(max_luminance)
  end
  mixed_frame  # Frame content unchanged, only hardware brightness affected
end
```

### 1.2 Unified Display API
```elixir
defmodule Octopus.App do
  # Configuration (called once during app initialization)
  def configure_display(opts \\ []) do
    config = %{
      layout: Keyword.get(opts, :layout, :gapped_panels),
      supports_rgb: Keyword.get(opts, :supports_rgb, true),
      supports_grayscale: Keyword.get(opts, :supports_grayscale, false),
      default_transparency: Keyword.get(opts, :transparency, 1.0)
    }
    # Creates buffers in mixer immediately
    Mixer.create_display_buffers(get_app_id(), config)
  end
  
  # Information access (replaces VirtualMatrix and installation access)
  def get_display_info() do
    Mixer.get_display_info()
  end
  
  # Display updates (replaces send_frame/send_canvas)
  def update_display(canvas, mode \\ :rgb) do
    Mixer.update_app_display(get_app_id(), canvas, mode)
  end
end
```

### 1.3 Display Buffer Management
- **Buffer Creation**: Automatic RGB/grayscale buffer creation based on app configuration
- **Layout Functions**: Panel range, coordinate mapping, and layout logic moved from VirtualMatrix to mixer
- **Memory Management**: Automatic cleanup when apps terminate

## Phase 2: App Migration and VirtualMatrix Elimination

### 2.1 Migration Patterns

#### VirtualMatrix Apps (Lemmings, SampleApp, Ocean, FairyDust, MarioRun)
```elixir
# Before
def app_init(_args) do
  virtual_matrix = VirtualMatrix.new(installation(), layout: :gapped_panels)
  {:ok, %State{virtual_matrix: virtual_matrix}}
end

def render(state) do
  canvas = create_canvas(state)
  VirtualMatrix.send_frame(state.virtual_matrix, canvas)
end

# After  
def app_init(_args) do
  Octopus.App.configure_display(layout: :gapped_panels)
  {:ok, %State{}}
end

def render(state) do
  canvas = create_canvas(state)
  Octopus.App.update_display(canvas)
end
```

#### Installation Access Apps (PixelFun, SpritesGrouped, Ocean, Starfield, DoomFire)
```elixir
# Before
defdelegate installation, to: Octopus
def render(state) do
  center_x = installation().center_x()
  width = installation().width()
  panel_count = installation().panel_count()
  # ...
end

# After
def render(state) do
  display_info = Octopus.App.get_display_info()
  center_x = display_info.width / 2 - 0.5  # Only PixelFun needs this
  width = display_info.width
  panel_count = display_info.panel_count
  # ...
end
```

#### Canvas.to_frame() Apps (Most apps)
```elixir
# Before
def render(state) do
  canvas = create_canvas(state)
  canvas |> Canvas.to_frame() |> send_frame()
end

# After
def render(state) do
  canvas = create_canvas(state)
  Octopus.App.update_display(canvas)
end
```

### 2.2 Layout Function Migration
Move VirtualMatrix functions to mixer:
- `panel_range(panel_id, axis)` → `display_info.panel_range.(panel_id, axis)`
- `panel_at_coord(x, y)` → `display_info.panel_at_coord.(x, y)`
- `panel_count()` → `display_info.panel_count`

## Phase 3: Multi-App Visual Mixing

### 3.1 App Selection and Transparency
```elixir
# Apps can set their own transparency and blend mode
Octopus.App.set_transparency(0.7)  # 70% opacity
Octopus.App.set_blend_mode(:screen)  # Use screen blending for bright overlays

# Manager can control which apps are active
AppManager.set_selected_apps([:app1, :app2])  # Multiple apps can be active

# Manager can override app settings
ManagerLive.set_app_transparency(:app1, 0.5)
ManagerLive.set_app_blend_mode(:app1, :multiply)  # Override app's blend mode
```

### 3.2 Visual Mixing Engine

#### Panel-Level Mixing Strategy
The mixer performs **panel-by-panel blending** to handle different display layouts efficiently:

```elixir
defp mixdown_displays(state) do
  selected_apps = get_selected_apps_with_transparency(state)
  panel_count = state.display_info.panel_count
  
  # Mix each physical panel separately (handles different layout modes)
  for panel_id <- 0..(panel_count - 1) do
    # Extract 8x8 panel pixels from each app's display buffer
    panel_canvases = 
      for {app_id, transparency} <- selected_apps do
        display_buffer = state.app_displays[app_id]
        extract_panel_pixels(display_buffer, panel_id)  # Returns 8x8 Canvas
      end
    
    # Blend all 8x8 panel canvases with transparency
    blend_panel_canvases(panel_canvases, transparencies)
  end
  |> join_panels_to_frame()  # Combine all panels into final frame
  |> generate_network_frame(state.output_mode)
end

# Panel extraction works regardless of display layout:
# - App A (gapped_panels): Extract pixels (24-31, 0-7) for panel 1  
# - App B (adjacent_panels): Extract pixels (8-15, 0-7) for panel 1
# - Both produce same 8x8 canvas that can be blended normally
```

#### Blending Modes Support
Leverages Canvas's existing professional blending capabilities:

```elixir
defp blend_panel_canvases(panel_canvases, blend_configs) do
  Enum.reduce(panel_canvases, Canvas.new(8, 8), fn {canvas, config}, acc ->
    %{mode: mode, transparency: alpha} = config
    Canvas.blend(acc, canvas, mode, alpha)
  end)
end
```

**Available blend modes** (from Canvas module):
- **`:add`** (default) - Natural LED light mixing, good for most cases
- **`:screen`** - Bright overlays without overexposure, excellent for text
- **`:multiply`** - Darkening effects, shadows, atmospheric effects
- **`:lighten`** - Highlighting, sparkle effects, bright accents
- **`:overlay`** - Dynamic mixing based on base brightness
- **`:darken`** - Takes darker colors, good for masking
- **`:subtract`** - Darkening by subtraction, special effects

#### Performance Analysis
- **Scale**: 12 panels × 64 pixels = 768 total pixels
- **Operations per frame**: ~6,144 simple operations (map lookups + arithmetic)
- **Target**: 60 FPS (16.67ms budget)
- **Assessment**: ✅ **Fast enough** - much simpler than existing app computations

### 3.3 Manager Live Integration
- Display running apps with transparency sliders
- Toggle app visibility
- Real-time transparency adjustment
- Multi-app selection interface

## Phase 4: RGB + Grayscale Support

### 4.1 Dual Buffer Support
```elixir
# Apps can maintain both buffer types
Octopus.App.configure_display(supports_rgb: true, supports_grayscale: true)

# Update specific buffer type
Octopus.App.update_display(rgb_canvas, :rgb)
Octopus.App.update_display(grayscale_canvas, :grayscale)
```

### 4.2 Output Modes
```elixir
# Mixer supports three output modes
Mixer.set_output_mode(:rgb)        # Send RGB frames only
Mixer.set_output_mode(:grayscale)  # Send WFrames only  
Mixer.set_output_mode(:masked)     # Use grayscale as alpha mask for RGB
```

### 4.3 Grayscale Mixing
- Blend grayscale buffers using same transparency system
- Convert final grayscale mixdown to WFrame packets
- Support grayscale-as-alpha-mask for RGB content

## Phase 5: Advanced Mixing and Canvas Integration

### 5.1 Canvas Integration
Move frame generation logic from Canvas to Mixer:
- `Canvas.to_frame()` → `Mixer.canvas_to_frame()`
- `Canvas.to_wframe()` → `Mixer.canvas_to_wframe()`
- Centralize all frame generation in mixer

### 5.2 Advanced Mixing Effects
- Alpha blending algorithms
- Additive blending modes
- Color space conversions
- Gamma correction integration

## Implementation Strategy

### Migration Order
1. **Core Infrastructure**: Mixer enhancement, display API
2. **Simple Apps First**: Canvas.to_frame() apps (easiest migration)
3. **VirtualMatrix Apps**: Apps using layout functions
4. **Complex Apps**: PixelFun, Ocean (most complex dependencies)
5. **Installation Cleanup**: Remove unused installation functions

### Backward Compatibility
- Maintain old APIs during migration period
- Add deprecation warnings
- Gradual migration app by app
- Remove old APIs only after all apps migrated

### Testing Strategy
- Test each migrated app individually
- Verify visual output matches exactly
- Test multi-app scenarios
- Performance benchmarking

## Benefits

### For App Developers
- **Simpler API**: Single `update_display()` call instead of multiple patterns
- **Better Isolation**: No need to understand installation details or frame protocols
- **Consistent Interface**: Same API regardless of display layout or panel configuration
- **Less Boilerplate**: No VirtualMatrix setup or installation delegation

### For System Architecture
- **Centralized Control**: All display logic in one place (mixer)
- **Multi-App Support**: Visual composition and mixing capabilities
- **Flexible Output**: Support for different display modes and effects
- **Better Performance**: Centralized buffer management and optimized mixing

### For User Experience
- **Multiple Apps**: Run multiple visual apps simultaneously
- **Real-time Control**: Adjust transparency and mixing in real-time
- **Visual Effects**: Support for advanced blending and effects
- **Consistent Behavior**: Unified behavior across all apps

## Validation

Our analysis confirmed this plan will successfully migrate all existing apps:

### Apps Analyzed
- **VirtualMatrix users**: Lemmings, SampleApp, Ocean, FairyDust, MarioRun ✅
- **Installation users**: PixelFun, SpritesGrouped, Starfield, DoomFire ✅  
- **Canvas.to_frame() users**: 20+ apps including Train, Senso, Matrix, etc. ✅
- **Special cases**: FrameRelay, Calibrator ✅

### Eliminated Dependencies
- ✅ **VirtualMatrix.ex**: All functionality moved to mixer
- ✅ **Direct installation access**: Replaced with unified display API
- ✅ **Complex app patterns**: Single consistent interface for all apps

This refactoring will modernize the entire Octopus display system while maintaining full backward compatibility during migration. 