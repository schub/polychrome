# Refactor: Button Event Handling System

## Overview

This commit represents a major refactor of the Octopus system's input event handling architecture. The changes introduce a new internal event structure (`ControllerEvent`) to simplify and standardize how button and joystick events are processed throughout the system, while maintaining backward compatibility with the existing protobuf network protocol.

## Motivation

The refactor addresses several architectural challenges in the previous event handling system:

1. **Complex Event Structure**: The previous system relied heavily on protobuf `InputEvent` structures throughout the internal codebase, mixing network protocol concerns with application logic.

2. **Inconsistent Joystick Handling**: Different parts of the system handled joystick events in varying ways, leading to maintenance complexity.

3. **Limited Semantic Clarity**: The protobuf format used low-level axis events that required translation to meaningful actions in multiple places.

4. **Missing Menu Button Support**: The system lacked proper support for menu buttons that installations might provide.

## Key Changes

### 1. New Internal Event Structure

**File**: `octopus/lib/octopus/controller_event.ex` (NEW)

Created `ControllerEvent` struct to replace internal use of protobuf `InputEvent`:
- **Button events**: Screen buttons 1-12 with `:press`/`:release` actions
- **Joystick movement**: Semantic directions (`:left`, `:right`, `:up`, `:down`, `:center`)
- **Joystick buttons**: Action buttons (`:a`, `:b`, `:menu`) with press/release states

### 2. Protocol Conversion Layer

**File**: `octopus/lib/octopus/input_adapter.ex`

Added conversion layer between protobuf network events and internal format:
- Converts incoming protobuf `InputEvent` to `ControllerEvent`
- Maps button types (e.g., `:BUTTON_1` → `{type: :button, button: 1}`)
- Translates joystick axis events to semantic directions
- Preserves network protocol compatibility while cleaning up internal APIs

### 3. Enhanced Button State Management

**File**: `octopus/lib/octopus/button_state.ex`

Modernized button state handling:
- Updated to work with new `ControllerEvent` format
- Improved joystick-to-button mapping logic
- Added support for menu button handling
- Maintained backward compatibility with existing `JoyState` system

### 4. Application API Updates

**File**: `octopus/lib/octopus/app.ex`

Updated the App behavior interface:
- Changed `handle_input/2` callback signature from `InputEvent` to `ControllerEvent`
- Updated documentation to reflect new event format
- All apps now receive clean, semantic event structures

### 5. Joystick Event Handler Improvements

**File**: `joystick/lib/joystick/event_handler.ex`

Enhanced physical joystick handling:
- Added smarter button mapping logic
- Improved support for different joystick configurations
- Better error handling and device detection
- Preparation for menu button support

### 6. Web Simulator Enhancements

**File**: `octopus/lib/octopus_web/live/pixels_live.ex`

Major improvements to the web-based input simulator:
- Complete rewrite of keyboard mapping system
- Added proper joystick simulation (2 joysticks with A/B buttons)
- Improved key mappings for better usability:
  - `A,S,D,F` for joystick 1 directions
  - `H,J,K,L` for joystick 2 directions
  - `Q,E` for joystick 1 A/B buttons
  - `N,M` for joystick 2 A/B buttons
  - Space bar as menu button
- Better visual feedback and state management

### 7. Application Updates

**Files**: All apps in `octopus/lib/octopus/apps/`

Updated all 19 applications to use the new event format:
- Replaced `InputEvent` with `ControllerEvent` in event handlers
- Simplified event matching with semantic field names
- Improved code readability and maintainability
- Enhanced error handling in several apps

### 8. Protocol Buffer Schema

**File**: `octopus/lib/octopus/protobuf/schema.pb.ex`

Updated protobuf definitions:
- Maintained existing button and joystick event types
- Added `BUTTON_MENU` support
- Reformatted for better code generation
- Preserved backward compatibility with external clients

### 9. Core System Components

**Files**: 
- `octopus/lib/octopus/mixer.ex`
- `octopus/lib/octopus/event_scheduler.ex`
- `octopus/lib/octopus/app_supervisor.ex`

Updated core components to:
- Pass through `ControllerEvent` instead of `InputEvent`
- Improve event routing and distribution
- Better error handling and logging
- Maintain system stability during the transition

## Technical Benefits

1. **Cleaner APIs**: Applications now work with semantic, purpose-built event structures instead of network protocol objects.

2. **Better Maintainability**: Event handling logic is centralized and consistent across the system.

3. **Enhanced Testability**: The new structure makes it easier to create test events and mock input scenarios.

4. **Future Extensibility**: The semantic approach makes it easier to add new input types without changing application code.

5. **Backward Compatibility**: External clients using the protobuf protocol continue to work unchanged.

## Statistics

- **28 files modified**
- **1 new file added** (`controller_event.ex`)
- **1,083 lines added, 663 lines removed**
- **All 19 applications updated**
- **Zero breaking changes to external protocol**

## Migration Impact

This refactor maintains complete backward compatibility:
- External clients continue to send protobuf `InputEvent` messages
- The conversion happens automatically at the network boundary
- No changes required to client applications or hardware controllers
- Web simulator provides enhanced testing capabilities

## Future Enhancements

This foundation enables future improvements:
- Enhanced menu button functionality across installations
- More sophisticated joystick gesture recognition
- Better support for different controller types
- Improved accessibility features
- Advanced input mapping and customization

---

This refactor represents a significant improvement in code quality, maintainability, and system architecture while preserving all existing functionality and compatibility. 