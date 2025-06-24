# Per-Panel Display Interface Extension Plan

## Overview

This document outlines a proposed extension to the Octopus display system that provides direct per-panel access for apps that work with individual panels rather than unified virtual matrices.

## Motivation

### Current Limitation
The current unified display API forces all apps to work through large virtual canvases (96px or 272px wide), even when their conceptual model is panel-based. This creates inefficiencies for apps that:

1. **Duplicate content across panels** (rickroll.ex - same animation on all panels)
2. **Manage independent panel state** (whackamole.ex - game state per panel/button)
3. **Don't benefit from cross-panel coordination** (pixel_fun.ex - mathematical functions per panel)

### Problems with Current Approach
- **Memory waste**: Creating large canvases to duplicate small content
- **CPU overhead**: Complex coordinate calculations and pixel copying
- **Code complexity**: Apps must handle panel positioning and layout math
- **Conceptual mismatch**: Panel-based apps forced into matrix thinking

## App Categories Analysis

### Category 1: Unified Canvas Apps ✅ (Current API Works Well)
Apps that benefit from single virtual matrix:
- `train.ex` - Scrolling landscape across panels
- `starfield.ex` - Continuous star field  
- `matrix.ex` - Rain effect spans panels
- `webpanimation.ex` - Full-width animations

**Need**: Single wide canvas (96px or 272px)

### Category 2: Per-Panel Apps 🎯 (Would Benefit from Extension)
Apps that treat panels independently:
- `rickroll.ex` - Same animation on every panel
- `whackamole.ex` - Game state per button/panel
- `space_invaders.ex` - Likely duplicated content per panel
- `pixel_fun.ex` - Mathematical functions per panel

**Would benefit from**: Direct access to individual 8x8 panel canvases

## Proposed Extended Interface

### New Configuration Options
```elixir
# Current unified interface (unchanged)
Octopus.App.configure_display(layout: :gapped_panels)   # Creates 272x8 buffer
Octopus.App.configure_display(layout: :adjacent_panels) # Creates 96x8 buffer

# New per-panel interface
Octopus.App.configure_display(interface: :per_panel)    # Creates array of 12x 8x8 buffers

# Future mixed interface
Octopus.App.configure_display(interface: :mixed)        # Background + per-panel overlays
```

### New Update Functions
```elixir
# Per-panel updates
Octopus.App.update_panel(panel_id, canvas_8x8)         # Update specific panel
Octopus.App.update_all_panels(canvas_8x8)             # Same content to all panels
Octopus.App.update_panels([0, 3, 7], canvas_8x8)     # Update subset of panels

# Panel information
Octopus.App.get_panel_count()                         # How many panels available
Octopus.App.get_panel(panel_id)                       # Read current panel state (optional)
```

## Implementation Architecture

### Extended Mixer State
```elixir
defmodule Octopus.Mixer do
  defmodule State do
    defstruct [
      app_displays: %{
        # Unified canvas apps (existing)
        "train_app" => %{
          type: :unified,
          rgb_buffer: %Canvas{width: 272, height: 8},
          display_info: %{layout: :gapped_panels, ...}
        },
        
        # Per-panel apps (new)
        "whackamole_app" => %{
          type: :per_panel,
          panel_buffers: [
            %Canvas{width: 8, height: 8},  # Panel 0
            %Canvas{width: 8, height: 8},  # Panel 1
            # ... 12 panels total
          ],
          display_info: %{interface: :per_panel, panel_count: 12}
        },
        
        # Mixed apps (future)
        "game_with_background" => %{
          type: :mixed,
          background_buffer: %Canvas{width: 272, height: 8},
          panel_overlays: [%Canvas{width: 8, height: 8}, ...],
          display_info: %{interface: :mixed, ...}
        }
      }
    ]
  end
end
```

### Frame Generation
```elixir
# Per-panel apps: Simple frame generation
defp panels_to_frame(panel_buffers) do
  panel_buffers
  |> Enum.reverse()  # Physical layout order
  |> Enum.reduce(&Canvas.join/2)
  |> Canvas.to_frame()
end

# Mixed apps: Composite background + overlays
defp mixed_to_frame(background, overlays, display_info) do
  # Extract background panels using existing logic
  background_panels = extract_panels_from_unified(background, display_info)
  
  # Blend with overlays
  composite_panels = 
    Enum.zip(background_panels, overlays)
    |> Enum.map(fn {bg, overlay} -> Canvas.blend(bg, overlay) end)
  
  panels_to_frame(composite_panels)
end
```

## Code Examples

### Rickroll App - Before vs After

#### Current Implementation (Inefficient)
```elixir
def app_init(_args) do
  Octopus.App.configure_display(layout: :adjacent_panels)  # Creates 96x8 canvas
  # ...
end

def handle_info(:tick, state) do
  {small_canvas, duration} = get_animation_frame()  # 8x8 animation
  
  # Must create big canvas and duplicate across 12 panels
  big_canvas = Canvas.new(96, 8)
  big_canvas = duplicate_across_panels(big_canvas, small_canvas)  # Complex logic
  Octopus.App.update_display(big_canvas)
end
```

#### Proposed Implementation (Efficient)
```elixir
def app_init(_args) do
  Octopus.App.configure_display(interface: :per_panel)     # Creates 12x 8x8 buffers
  # ...
end

def handle_info(:tick, state) do
  {small_canvas, duration} = get_animation_frame()  # 8x8 animation
  
  # Directly update all panels with same content
  Octopus.App.update_all_panels(small_canvas)       # Simple, efficient
end
```

### Whackamole App - Before vs After

#### Current Implementation (Complex)
```elixir
def render_game(game_state) do
  big_canvas = Canvas.new(96, 8)
  
  # Complex: Must calculate panel positions and overlay
  for {panel_id, panel_state} <- game_state.panels do
    panel_canvas = render_panel(panel_state)              # 8x8 canvas
    {x, y} = calculate_panel_position(panel_id)           # Layout math
    big_canvas = Canvas.overlay(big_canvas, panel_canvas, offset: {x, y})
  end
  
  Octopus.App.update_display(big_canvas)
end
```

#### Proposed Implementation (Simple)
```elixir
def render_game(game_state) do
  # Simple: Direct panel updates
  for {panel_id, panel_state} <- game_state.panels do
    panel_canvas = render_panel(panel_state)              # 8x8 canvas
    Octopus.App.update_panel(panel_id, panel_canvas)      # Direct update
  end
end
```

## Benefits

### Performance Benefits
- **Memory efficiency**: No large intermediate canvases for duplicated content
- **CPU efficiency**: No coordinate transformations or pixel copying for per-panel apps
- **Network efficiency**: Only changed panels need updates (future optimization)

### Developer Experience
- **Conceptual clarity**: App logic matches panel-based hardware
- **Reduced complexity**: No layout math for panel-based apps
- **Better patterns**: Cleaner separation between unified and per-panel approaches

### System Architecture
- **Flexibility**: Apps choose the most appropriate interface
- **Backward compatibility**: Existing unified canvas apps unchanged
- **Future extensibility**: Foundation for advanced mixing scenarios

## Implementation Phases

### Phase 1: Core Per-Panel Interface
- Add `interface: :per_panel` configuration option
- Implement `update_panel/2` and `update_all_panels/1` functions
- Add per-panel buffer management in Mixer
- Update frame generation for per-panel apps

### Phase 2: Enhanced Per-Panel Features
- Implement `update_panels/2` for subset updates
- Add `get_panel_count/0` and `get_panel/1` functions
- Optimize frame generation (only update changed panels)

### Phase 3: Mixed Interface (Future)
- Add `interface: :mixed` for background + overlay scenarios
- Implement background/overlay blending
- Support complex multi-layer scenarios

## Design Questions to Resolve

1. **Panel Addressing**: Physical order (0-11) or logical addressing?
2. **Partial Updates**: How granular should panel update batching be?
3. **Panel State Query**: Should apps read current panel state for optimization?
4. **Transition Support**: How do transitions work with per-panel apps?
5. **Multi-app Mixing**: How do per-panel apps mix with unified canvas apps?

## Compatibility Strategy

### Backward Compatibility
- All existing apps continue working without changes
- Current unified canvas interface remains primary
- Per-panel interface is purely additive

### Migration Path
1. Identify apps that would benefit from per-panel interface
2. Provide migration examples and documentation
3. Optional: Add compatibility helpers for gradual migration

## Future Enhancements

### Advanced Panel Features
```elixir
# Panel-specific effects
Octopus.App.set_panel_brightness(panel_id, 0.5)
Octopus.App.set_panel_effect(panel_id, :fade_in)

# Panel groups
Octopus.App.update_panel_group(:left_half, canvas)   # Panels 0-5
Octopus.App.update_panel_group(:right_half, canvas)  # Panels 6-11
```

### Performance Optimizations
- Dirty panel tracking (only update changed panels)
- Panel-level frame caching
- Parallel panel processing

## Conclusion

The per-panel interface extension addresses a fundamental mismatch between app concepts and the current unified canvas approach. It provides:

1. **Efficiency** for apps that work with individual panels
2. **Simplicity** for developers building panel-based apps  
3. **Flexibility** to choose the right interface for each app type
4. **Future-proofing** for advanced mixing and effects

This extension complements rather than replaces the current system, providing the right tool for each type of app while maintaining full backward compatibility.

---

*This plan should be implemented after completing the current display refactoring plan (Phase 2B migration and Canvas.to_frame elimination).* 