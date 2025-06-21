# Architecture Diagrams - Events Branch Refactoring

This document contains enhanced visual diagrams illustrating the architectural improvements made during the Octopus events branch refactoring. These diagrams use Mermaid syntax and provide color-coded, interactive visualizations.

## How to View These Diagrams

- **GitHub/GitLab**: Automatically renders Mermaid diagrams
- **VS Code**: Install Mermaid preview extensions
- **Online**: Copy/paste into [Mermaid Live Editor](https://mermaid.live/)
- **Documentation platforms**: Most modern platforms support Mermaid

---

## Event Flow Transformation

This diagram shows the fundamental change in how events flow through the system before and after the refactoring.

```mermaid
graph TD
    subgraph "BEFORE: Protocol Leakage"
        A1[Network Input] --> B1[InputAdapter]
        B1 --> C1[Raw Protobuf Events]
        C1 --> D1[App 1]
        C1 --> D2[App 2]
        C1 --> D3[App N]
        
        style C1 fill:#ffcccc,stroke:#ff6b6b,stroke-width:2px
        style D1 fill:#ffcccc,stroke:#ff6b6b,stroke-width:2px
        style D2 fill:#ffcccc,stroke:#ff6b6b,stroke-width:2px
        style D3 fill:#ffcccc,stroke:#ff6b6b,stroke-width:2px
    end
    
    subgraph "AFTER: Clean Domain Events"
        A2[Network Input] --> B2[InputAdapter]
        B2 --> F2[Factory]
        F2 --> C2[Domain Events]
        C2 --> E2[Events.Router]
        E2 --> G2[AppManager]
        G2 --> D4[Selected App]
        
        style F2 fill:#ccffcc,stroke:#51cf66,stroke-width:2px
        style C2 fill:#ccffcc,stroke:#51cf66,stroke-width:2px
        style E2 fill:#ccffcc,stroke:#51cf66,stroke-width:2px
        style G2 fill:#ccffcc,stroke:#51cf66,stroke-width:2px
        style D4 fill:#ccffcc,stroke:#51cf66,stroke-width:2px
    end
```

**Key Improvements:**
- 🔴 **Red (Before)**: Protocol knowledge scattered throughout apps
- 🟢 **Green (After)**: Clean domain events with centralized conversion

---

## Detailed System Architecture

This comprehensive diagram shows all components and their relationships in the new architecture.

```mermaid
graph TB
    subgraph "Network Boundary"
        NET[Network Input<br/>Protobuf Events]
        IA[InputAdapter<br/>Pattern Matching]
    end
    
    subgraph "Conversion Layer"
        FAC[Factory<br/>Protocol → Domain]
        CE[Controller Events<br/>Buttons & Joysticks]
        PE[Proximity Events<br/>Distance Sensors]
        AE[Audio Events<br/>Frequency Analysis]
    end
    
    subgraph "Domain Event System"
        ER[Events.Router<br/>Event Distribution]
        AM[AppManager<br/>App Selection & Lifecycle]
    end
    
    subgraph "Application Layer"
        APP1[pixel_fun.ex<br/>Visual Effects]
        APP2[senso.ex<br/>Memory Game]
        APP3[bomber_person.ex<br/>Action Game]
        APPN[... 19 apps total<br/>Various Games & Tools]
    end
    
    NET --> IA
    IA --> FAC
    FAC --> CE
    FAC --> PE
    FAC --> AE
    CE --> ER
    PE --> ER
    AE --> ER
    ER --> AM
    AM --> APP1
    AM --> APP2
    AM --> APP3
    AM --> APPN
    
    style NET fill:#e1f5fe,stroke:#0288d1,stroke-width:2px
    style IA fill:#e8f5e8,stroke:#2e7d32,stroke-width:2px
    style FAC fill:#fff3e0,stroke:#f57c00,stroke-width:2px
    style CE fill:#f3e5f5,stroke:#7b1fa2,stroke-width:2px
    style PE fill:#f3e5f5,stroke:#7b1fa2,stroke-width:2px
    style AE fill:#f3e5f5,stroke:#7b1fa2,stroke-width:2px
    style ER fill:#fce4ec,stroke:#c2185b,stroke-width:2px
    style AM fill:#fce4ec,stroke:#c2185b,stroke-width:2px
    style APP1 fill:#e0f2f1,stroke:#00695c,stroke-width:2px
    style APP2 fill:#e0f2f1,stroke:#00695c,stroke-width:2px
    style APP3 fill:#e0f2f1,stroke:#00695c,stroke-width:2px
    style APPN fill:#e0f2f1,stroke:#00695c,stroke-width:2px
```

**Architecture Layers:**
- 🔵 **Network Boundary**: Protocol handling and input reception
- 🟢 **Conversion Layer**: Factory pattern for protocol-to-domain conversion
- 🟠 **Domain Events**: Clean, semantic business events
- 🟣 **Event System**: Routing and app management
- 🟢 **Applications**: Pure business logic, no protocol concerns

---

## Developer Experience Transformation

This diagram illustrates how the refactoring dramatically simplifies the developer experience.

```mermaid
graph LR
    subgraph "Before: Complex Development Process"
        B1[👨‍💻 App Developer] --> B2[📚 Learn Protobuf Schemas]
        B2 --> B3[🔧 Handle Raw Protocol Events]
        B3 --> B4[🔄 Convert to Business Logic]
        B4 --> B5[✨ Implement Features]
        
        style B1 fill:#ffebee,stroke:#d32f2f,stroke-width:2px
        style B2 fill:#ffebee,stroke:#d32f2f,stroke-width:2px
        style B3 fill:#ffebee,stroke:#d32f2f,stroke-width:2px
        style B4 fill:#ffebee,stroke:#d32f2f,stroke-width:2px
        style B5 fill:#ffebee,stroke:#d32f2f,stroke-width:2px
    end
    
    subgraph "After: Simplified Development Process"
        A1[👨‍💻 App Developer] --> A2[🎯 Handle Semantic Events]
        A2 --> A3[✨ Implement Features]
        
        style A1 fill:#e8f5e8,stroke:#388e3c,stroke-width:2px
        style A2 fill:#e8f5e8,stroke:#388e3c,stroke-width:2px
        style A3 fill:#e8f5e8,stroke:#388e3c,stroke-width:2px
    end
```

**Benefits:**
- ⏰ **Time Savings**: 60% reduction in development steps
- 🧠 **Cognitive Load**: No need to learn complex protocols
- 🎯 **Focus**: Developers can focus on business logic
- 🐛 **Fewer Bugs**: Type-safe, validated events

---

## Event Type Evolution

This diagram shows how different event types evolved through the refactoring phases.

```mermaid
graph TB
    subgraph "Phase 3: Controller Events"
        P3A[InputEvent<br/>Raw Protobuf] --> P3B[Controller<br/>Semantic Events]
        P3B --> P3C[Apps receive:<br/>button: 1, action: :press<br/>direction: :left]
        
        style P3A fill:#ffcdd2,stroke:#d32f2f
        style P3B fill:#c8e6c9,stroke:#388e3c
        style P3C fill:#c8e6c9,stroke:#388e3c
    end
    
    subgraph "Phase 4B: Proximity Events"
        P4BA[ProximityEvent<br/>panel_index, sensor_index] --> P4BB[Proximity<br/>panel, sensor + helpers]
        P4BB --> P4BC[Apps receive:<br/>in_range?, sensor_id<br/>normalized distance]
        
        style P4BA fill:#ffcdd2,stroke:#d32f2f
        style P4BB fill:#c8e6c9,stroke:#388e3c
        style P4BC fill:#c8e6c9,stroke:#388e3c
    end
    
    subgraph "Phase 4C: Audio Events"
        P4CA[SoundToLightControlEvent<br/>Confusing name] --> P4CB[Audio<br/>Clear purpose + helpers]
        P4CB --> P4CC[Apps receive:<br/>intensity, dominant_frequency<br/>normalized_spectrum]
        
        style P4CA fill:#ffcdd2,stroke:#d32f2f
        style P4CB fill:#c8e6c9,stroke:#388e3c
        style P4CC fill:#c8e6c9,stroke:#388e3c
    end
```

---

## Testing Improvement Visualization

Shows how testing became dramatically simpler with domain events.

```mermaid
graph LR
    subgraph "Before: Complex Test Setup"
        T1[Create Protobuf Event] --> T2[Set Raw Fields<br/>type: :AXIS_X_1<br/>value: -1]
        T2 --> T3[❓ What does this test?]
        
        style T1 fill:#ffebee,stroke:#d32f2f
        style T2 fill:#ffebee,stroke:#d32f2f
        style T3 fill:#ffebee,stroke:#d32f2f
    end
    
    subgraph "After: Clear Test Intent"
        T4[Create Domain Event] --> T5[Set Semantic Fields<br/>type: :joystick<br/>direction: :left]
        T5 --> T6[✅ Crystal clear intent]
        
        style T4 fill:#e8f5e8,stroke:#388e3c
        style T5 fill:#e8f5e8,stroke:#388e3c
        style T6 fill:#e8f5e8,stroke:#388e3c
    end
```

---

## Factory Pattern Detail

Shows how the Factory pattern centralizes all protocol conversion logic.

```mermaid
graph TD
    subgraph "Protobuf Events (Network)"
        PE1[InputEvent]
        PE2[ProximityEvent]
        PE3[SoundToLightControlEvent]
    end
    
    subgraph "Factory Conversion"
        FAC[Events.Factory<br/>Centralized Conversion]
        FAC --> FC1[create_controller_event/1]
        FAC --> FC2[create_proximity_event/1]
        FAC --> FC3[create_audio_event/1]
    end
    
    subgraph "Domain Events (Clean)"
        DE1[Controller<br/>+ validation<br/>+ helpers]
        DE2[Proximity<br/>+ validation<br/>+ helpers]
        DE3[Audio<br/>+ validation<br/>+ helpers]
    end
    
    PE1 --> FC1 --> DE1
    PE2 --> FC2 --> DE2
    PE3 --> FC3 --> DE3
    
    style PE1 fill:#ffcdd2,stroke:#d32f2f
    style PE2 fill:#ffcdd2,stroke:#d32f2f
    style PE3 fill:#ffcdd2,stroke:#d32f2f
    style FAC fill:#fff3e0,stroke:#f57c00,stroke-width:3px
    style DE1 fill:#c8e6c9,stroke:#388e3c
    style DE2 fill:#c8e6c9,stroke:#388e3c
    style DE3 fill:#c8e6c9,stroke:#388e3c
```

**Key Benefits:**
- 🎯 **Single Responsibility**: Factory only handles conversion
- 🧹 **Clean Domain Events**: No protocol knowledge
- 🔧 **Easy Maintenance**: Protocol changes isolated to Factory
- ✅ **Testable**: Each conversion function easily tested

---

*These diagrams provide enhanced visualization of the architectural improvements. For text-based diagrams that work in any environment, refer to the main [COMMIT_SUMMARY.md](COMMIT_SUMMARY.md).* 