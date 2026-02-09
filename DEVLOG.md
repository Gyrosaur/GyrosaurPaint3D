# GyrosaurPaint3D v3 Development Log

## Project: Brush Studio Implementation

---

## 2025-02-04 – Session Start

### PLAN: Phase 1 – Brush Preset System

**Goal:** Create a JSON-based brush definition system with UI controls

**Tasks:**
1. [x] Create `BrushDefinition.swift` – Codable struct for all brush parameters
2. [x] Create `BrushPresetManager.swift` – Load/save/manage presets
3. [x] Create `BrushStudioView.swift` – Main UI for editing brushes
4. [x] Create default brush presets (JSON files)
5. [ ] Integrate with existing `DrawingEngine.swift`
6. [x] Add Brush Studio access from main UI

**Brush Parameters to support:**
- Geometry: particleSize, sizeVariation, shape
- Stroke: spacing, jitter, smoothing
- Emission: rate, trailLength
- Color: mode (solid/gradient/velocity), gradientStops
- Physics: gravity, turbulence, lifetime

**Files to create:**
- `GyroAR3DPaint/BrushStudio/BrushDefinition.swift`
- `GyroAR3DPaint/BrushStudio/BrushPresetManager.swift`
- `GyroAR3DPaint/BrushStudio/BrushStudioView.swift`
- `GyroAR3DPaint/BrushStudio/BrushParameterControls.swift`
- `GyroAR3DPaint/BrushPresets/` (default JSON presets)

---

## 2025-02-04 – Progress Updates

### ✅ COMPLETED: BrushDefinition.swift
- Created comprehensive brush definition struct with all parameter groups
- GeometryParams, StrokeParams, EmissionParams, ColorMode, PhysicsParams
- Default presets: Smooth, Ribbon, Sparkle, Helix, Vine, Neon
- SIMD3 and ClosedRange Codable extensions for JSON serialization

### ✅ COMPLETED: BrushPresetManager.swift
- Preset loading/saving with UserDefaults persistence
- User preset management (create, update, delete, duplicate)
- Export/import functionality for sharing presets

### ✅ COMPLETED: BrushStudioView.swift
- Full tabbed interface: Presets, Geometry, Stroke, Emission, Color, Physics
- Parameter sliders and controls for all brush properties
- Preset grid with category filtering
- Live preview canvas
- Save as new preset dialog

### ✅ COMPLETED: ContentView integration (partial)
- Added Brush Studio button to toolbar
- BrushPresetManager instantiated as @StateObject
- showBrushStudio state and modal presentation working

---

## 2025-02-04 – Session 2: Integration Phase

### ARCHITECTURE DECISION:
- **Brush Palette (existing)** = Quick select, stays as-is
- **Brush Studio (new)** = Deep customization layer, separate system

Quick palette picks base brush → Studio allows fine-tuning → Custom presets saved to Studio

### 🔄 IN PROGRESS: Full Integration

**Goal:** Make Brush Studio parameters actually affect drawing

**Tasks:**
1. [x] DrawingEngine gets reference to BrushPresetManager
2. [x] When preset changes, DrawingEngine updates its parameters
3. [x] Apply: spacing, jitter, sizeVariation, physics to actual strokes
4. [ ] StrokeRenderer reads color mode parameters from preset (gradient, rainbow)

**Files modified:**
- `DrawingEngine.swift` – Added:
  - `activeBrushPreset: BrushDefinition` property
  - `useStudioPreset: Bool` toggle
  - Computed properties: presetJitter, presetSizeVariation, presetSpacing, presetSmoothing, presetGravity, presetTurbulence
  - `applyPreset()`, `disableStudioPreset()`, `toggleStudioPreset()` methods
  - `addPoint()` now applies preset parameters (jitter, spacing, size variation, gravity, turbulence)

- `BrushStudioView.swift` – Added:
  - `onApply: ((BrushDefinition) -> Void)?` callback
  - `onDismiss: (() -> Void)?` callback
  - Two initializers (convenience without callbacks, full with callbacks)

- `ContentView.swift` – Updated:
  - `brushStudioModal` now passes onApply/onDismiss callbacks
  - Brush Studio toolbar button highlights when `useStudioPreset` is active
  - Brush palette selection disables studio preset

### ✅ INTEGRATION STATUS: Core functionality complete

**What works now:**
- Open Brush Studio → adjust parameters → Apply → parameters affect drawing
- Jitter, size variation, spacing, gravity, turbulence all applied in real-time
- Toolbar shows highlight when studio preset is active
- Selecting from brush palette automatically disables studio preset
- Two systems coexist: quick palette vs deep studio

**Next steps for Phase 2:**
- [ ] StrokeRenderer color mode integration (gradient along stroke, rainbow, velocity-based)
- [ ] Live preview in Brush Studio showing actual AR strokes
- [ ] Emission params (burst, trail) integration

---


## 2025-02-04 – Session 3: Phase 2 - Color Mode Integration

### GOAL: StrokeRenderer reads ColorMode from preset

**Tasks:**
1. [ ] Store activeBrushPreset in Stroke struct
2. [ ] StrokeRenderer reads color mode from stroke's preset
3. [ ] Implement gradient color along stroke
4. [ ] Implement rainbow/hue shift mode
5. [ ] Implement noise-based coloring

**Color modes to support:**
- `solid` – current behavior (use stroke color)
- `gradient` – interpolate between gradient stops along stroke length
- `rainbow` – hue shifts along stroke
- `velocity` – color based on drawing speed
- `noise` – perlin-style color variation


### ✅ COMPLETED: Color Mode Integration

**Changes made:**

1. **DrawingEngine.swift:**
   - `Stroke` struct now has `brushPreset: BrushDefinition?`
   - `startDrawing()` attaches active preset to new strokes

2. **StrokeRenderer.swift:**
   - Added `pointIndex` parameter to `pointColor()` method
   - New `applyColorMode()` method handles all color modes:
     - `.solid` – default behavior
     - `.gradient` – interpolates between gradient stops along stroke
     - `.rainbow` – hue shifts along stroke based on hueShiftOverStroke
     - `.velocity` – color based on drawing speed (slow=blue, fast=red)
     - `.noise` – Perlin noise-based color variation
   - Added `interpolateGradient()` for smooth gradient transitions
   - Added `perlinNoise()` with helper functions (fade, lerp, hash)
   - Updated `makeTube()` and `makeRibbon()` to detect preset color modes

**Color Mode Features:**

| Mode | Description |
|------|-------------|
| Solid | Use base stroke color |
| Gradient | Custom color stops along stroke length |
| Rainbow | Automatic hue cycling (configurable cycles) |
| Velocity | Fast=red, slow=blue (or custom velocity map) |
| Noise | 3D Perlin noise varies hue & saturation |

**Usage:**
1. Open Brush Studio
2. Go to "Color" tab
3. Select mode (Gradient, Rainbow, Noise, etc.)
4. Configure parameters (gradient stops, hue shift cycles, noise scale)
5. Apply preset
6. Draw – colors change along stroke!



---

## 2025-02-04 – Session 4: Brush Studio as Standalone Mode

### USER REQUEST:
- Brush Studio should be a **separate mode** selectable from app launch (like AR Draw)
- Not a popup/modal on top of drawing view
- Dedicated workspace for brush creation

### BRUSH STUDIO REQUIREMENTS:

**Layout:**
- Left panel: Node editor OR parameter controls
- Right panel: Preset browser / save/load
- Bottom-left: **Test canvas** – mini AR world with white background for live brush testing
- Top: Toolbar (save, load, export, import)

**Test Canvas features:**
- Same AR rendering as main app
- White/neutral background
- Draw to test brush in real-time
- Clear button to reset

**Workflow:**
1. App launch → Choose: "AR Draw" or "Brush Studio"
2. In Studio: Edit brush parameters / nodes
3. Test brush in mini canvas
4. Save preset
5. Exit to main menu or switch to AR Draw with new brush

**Technical approach:**
- Create `BrushStudioMode.swift` – Full-screen studio view
- Create `BrushTestCanvas.swift` – Mini AR view for testing
- Modify `ModeSelectionView.swift` – Add Brush Studio option
- Brush changes may require loading time → show progress bar

### TASKS:
1. [ ] Create BrushStudioMode.swift (main studio layout)
2. [ ] Create BrushTestCanvas.swift (mini AR test view)
3. [ ] Add "Brush Studio" button to ModeSelectionView
4. [ ] Implement parameter panels (Geometry, Stroke, Color, Physics)
5. [ ] Connect test canvas to live brush preview
6. [ ] Add save/load/export functionality
7. [ ] Progress bar for brush compilation if needed

---


### ✅ COMPLETED: Brush Studio as Standalone Mode

**New files created:**

1. **BrushStudioMode.swift** (245 lines)
   - Full-screen studio layout
   - Left panel: Parameter tabs (Presets, Geometry, Stroke, Color, Physics, Emission)
   - Right panel: Test canvas + preset info
   - Header with Exit button and Save
   - Compilation progress overlay (for future use)

2. **StudioPanels.swift** (632 lines)
   - `PresetsPanel` – Category filter + preset grid
   - `GeometryPanel` – Shape, size, variation, aspect ratio
   - `StrokePanel` – Spacing, smoothing, jitter
   - `ColorPanel` – Color mode picker (Solid, Gradient, Rainbow, Velocity, Noise)
   - `GradientEditorPanel` – Visual gradient stop editor
   - `PhysicsPanel` – Gravity, turbulence, drag, attraction
   - `EmissionPanel` – Rate, burst, trail, lifetime
   - UI components: PanelHeader, StudioSlider, StudioStepper

3. **BrushTestCanvas.swift** (317 lines)
   - Mini AR view with white background
   - `TestDrawingEngine` for test strokes
   - `TestARViewContainer` with pan gesture
   - `TestStrokeRenderer` for live preview
   - Clear button and drawing indicator

**Modified files:**

- `ModeSelectionView.swift` – Added `.brushStudio` case to AppMode enum
- `GyroAR3DPaintApp.swift` – Added mode selection flow, routes to BrushStudioMode
- `project.pbxproj` – Added all 6 BrushStudio files to Xcode project

**App Flow:**
```
App Launch
    ↓
Performance Selection (first time)
    ↓
Mode Selection:
├── Real World AR → ContentView
├── White Room → ContentView  
└── Brush Studio → BrushStudioMode
```

**Brush Studio Layout:**
```
┌─────────────────────────────────────────────────┐
│ [Exit]        BRUSH STUDIO           [Save]     │
├────────────────────────┬────────────────────────┤
│ [Presets][Shape][Stroke][Color][Physics][Parts] │
├────────────────────────┼────────────────────────┤
│                        │  Smooth                │
│   Parameter            │  [Basic]               │
│   Controls             ├────────────────────────┤
│                        │                        │
│   - Sliders            │   TEST CANVAS          │
│   - Pickers            │   (mini AR view)       │
│   - Steppers           │                        │
│                        │   Draw here to test    │
│                        │                        │
│                        ├────────────────────────┤
│                        │ [Clear] [Save] [Reset] │
└────────────────────────┴────────────────────────┘
```


---

## 2025-02-04 – Session 5: Brush DSL (Domain Specific Language)

### GOAL: Text prompt field that parses commands into BrushDefinition

**Approach:** 
- No LLM, pure keyword/command parsing
- User writes DSL commands
- Parser converts to BrushDefinition changes

### DSL DESIGN:

**Format:** `property value` or `property.subproperty value`

**Examples:**
```
size 0.02
jitter 0.5
color rainbow
gravity -0.01
shape sphere
spacing 0.3
turbulence 0.8
trail 5
burst 3
```

**Compound commands:**
```
size 0.02 jitter 0.5 color rainbow
```

**Presets shorthand:**
```
preset sparkle
preset neon
```

### TASKS:
1. [ ] Create BrushDSLParser.swift
2. [ ] Add prompt TextField to BrushStudioMode
3. [ ] Parse on Enter/Apply
4. [ ] Show error feedback for invalid commands
5. [ ] Document all available commands



### ✅ COMPLETED: Brush DSL Parser

**New file:** `BrushDSLParser.swift` (402 lines)

**DSL Syntax:**

```
COMMAND VALUE [COMMAND VALUE ...]
```

**Available Commands:**

| Category | Command | Values | Example |
|----------|---------|--------|---------|
| **GEOMETRY** | | | |
| | `size` | 0.002-0.1 | `size 0.02` |
| | `variation` | 0-1 | `variation 0.5` |
| | `shape` | sphere/cube/cylinder/cone/ribbon | `shape ribbon` |
| | `segments` | 3-32 | `segments 12` |
| | `aspect` | 0.1-10 | `aspect 2.0` |
| **STROKE** | | | |
| | `spacing` | 0.05-2 | `spacing 0.3` |
| | `jitter` | 0-1 | `jitter 0.5` |
| | `smoothing` | 0-1 | `smoothing 0.8` |
| | `pressure` | 0-3 | `pressure 1.5` |
| | `anglefollow` | 0-1 | `anglefollow 1.0` |
| **COLOR** | | | |
| | `color` | solid/gradient/rainbow/velocity/noise | `color rainbow` |
| | `hueshift` | 0-10 | `hueshift 2.0` |
| | `noisescale` | 0.1-20 | `noisescale 3.0` |
| **PHYSICS** | | | |
| | `gravity` | -0.05 to 0.05 | `gravity -0.01` |
| | `turbulence` | 0-1 | `turbulence 0.5` |
| | `drag` | 0-1 | `drag 0.3` |
| | `attract` | -1 to 1 | `attract 0.5` |
| **PARTICLES** | | | |
| | `rate` | 0.1-20 | `rate 2.0` |
| | `burst` | 1-50 | `burst 3` |
| | `trail` | 0-30 | `trail 5` |
| | `lifetime` | 0-30 | `lifetime 3.0` |
| **PRESETS** | | | |
| | `preset` | smooth/sparkle/ribbon/helix/vine/neon | `preset sparkle` |
| | `reset` | (no value) | `reset` |

**Special values:**
- `random` – generates random value in valid range

**Compound commands:**
```
size 0.02 jitter 0.5 color rainbow gravity -0.01
```

**UI Integration:**
- Prompt field at top of left panel
- Enter or Play button to apply
- ? button shows help overlay
- Success/error feedback below field


---

## 2025-02-04 – Session 6: JavaScriptCore Brush Scripting

### GOAL: Full JavaScript scripting for brush creation

**Why JS:**
- Built into iOS (JavaScriptCore framework)
- GPT/Claude knows JS perfectly
- Loops, functions, math, conditions, objects
- Like Blender's Python but for brushes

### ARCHITECTURE:

```
User writes JS (or GPT generates it)
         ↓
    [JS Code]
         ↓
  JavaScriptCore Engine
         ↓
  BrushDefinition object
         ↓
    Render in AR
```

### JS API DESIGN:

```javascript
// Global brush object
brush.geometry.baseSize = 0.02;
brush.geometry.shape = "sphere"; // sphere/cube/cylinder/cone/ribbon
brush.geometry.sizeVariation = 0.3;
brush.geometry.segments = 12;

brush.stroke.spacing = 0.3;
brush.stroke.jitter = 0.5;
brush.stroke.smoothing = 0.8;

brush.color.mode = "rainbow"; // solid/gradient/rainbow/velocity/noise
brush.color.hueShift = 2.0;
brush.color.gradient = [
    { pos: 0.0, h: 0.0, s: 1.0, b: 1.0 },
    { pos: 1.0, h: 0.6, s: 1.0, b: 1.0 }
];

brush.physics.gravity = [0, -0.01, 0];
brush.physics.turbulence = 0.5;
brush.physics.drag = 0.3;

brush.emission.rate = 2.0;
brush.emission.burst = 3;
brush.emission.trail = 5;

// Per-point callback (advanced)
brush.onPoint = function(ctx) {
    // ctx.index, ctx.position, ctx.velocity, ctx.time
    return {
        size: 0.01 + Math.sin(ctx.index * 0.2) * 0.005,
        hue: (ctx.index * 10) % 1.0
    };
};

// Utility functions
let x = math.sin(0.5);
let r = math.random();
let c = color.hsl(0.5, 1.0, 0.5);
let v = vec3(0, 1, 0);
```

### TASKS:
1. [ ] Create BrushScriptEngine.swift (JavaScriptCore wrapper)
2. [ ] Define JS API (brush object, math, color, vec3 helpers)
3. [ ] Add code editor to BrushStudioMode
4. [ ] Execute script → update BrushDefinition
5. [ ] Error handling with line numbers
6. [ ] Example scripts library



### ✅ COMPLETED: JavaScriptCore Brush Scripting

**New file:** `BrushScriptEngine.swift` (540 lines)

**Features:**
- Full JavaScript execution via iOS JavaScriptCore
- GPT/Claude can generate brush scripts
- Loops, functions, math, conditions - all work

## JAVASCRIPT API REFERENCE

### Global `brush` Object:

```javascript
// Name
brush.name = "My Brush";

// Geometry
brush.geometry.baseSize = 0.015;      // meters
brush.geometry.sizeVariation = 0.3;   // 0-1
brush.geometry.shape = "sphere";      // sphere/cube/cylinder/cone/ribbon
brush.geometry.aspectRatio = 2.0;
brush.geometry.segments = 12;

// Stroke
brush.stroke.spacing = 0.3;           // point density
brush.stroke.jitter = 0.5;            // position randomness
brush.stroke.jitterScale = 1.0;
brush.stroke.smoothing = 0.8;
brush.stroke.pressureResponse = 1.5;
brush.stroke.angleFollow = 1.0;

// Color
brush.color.mode = "rainbow";         // solid/gradient/rainbow/velocity/noise
brush.color.hueShift = 2.0;           // rainbow cycles
brush.color.noiseScale = 3.0;
brush.color.noiseSpeed = 1.0;
brush.color.gradient = [
    { pos: 0.0, h: 0.0, s: 1.0, b: 1.0 },
    { pos: 1.0, h: 0.6, s: 1.0, b: 1.0 }
];

// Physics
brush.physics.gravity = [0, -0.01, 0]; // [x, y, z]
brush.physics.turbulence = 0.5;
brush.physics.turbulenceScale = 1.0;
brush.physics.drag = 0.3;
brush.physics.velocityInherit = 0.5;
brush.physics.attract = 0.2;

// Emission
brush.emission.rate = 2.0;
brush.emission.burstCount = 3;
brush.emission.burstSpread = 0.02;
brush.emission.trailLength = 5;
brush.emission.trailFade = 0.7;
brush.emission.lifetime = 3.0;        // 0 = permanent
brush.emission.fadeIn = 0.1;
brush.emission.fadeOut = 0.5;
```

### Per-Point Callback (Advanced):

```javascript
brush.onPoint = function(ctx) {
    // ctx.index - point index in stroke
    // ctx.position - [x, y, z]
    // ctx.velocity - [x, y, z]
    // ctx.time - seconds since stroke start
    
    return {
        size: 0.01 + Math.sin(ctx.index * 0.2) * 0.005,
        hue: (ctx.index * 10) % 1.0,
        saturation: 1.0,
        brightness: 1.0,
        alpha: 1.0,
        offset: [0, 0, 0]
    };
};
```

### Helper Functions:

```javascript
// Math
math.sin(x), math.cos(x), math.tan(x)
math.abs(x), math.sqrt(x), math.pow(x, y)
math.min(a, b), math.max(a, b)
math.floor(x), math.ceil(x), math.round(x)
math.random()
math.PI
math.lerp(a, b, t)           // linear interpolation
math.clamp(x, min, max)
math.map(x, inMin, inMax, outMin, outMax)
math.smoothstep(edge0, edge1, x)
math.noise(x)                // 1D noise
math.noise2d(x, y)           // 2D noise
math.noise3d(x, y, z)        // 3D noise

// Color
color.hsl(h, s, l)
color.hsla(h, s, l, a)
color.rgb(r, g, b)
color.rgba(r, g, b, a)
color.stop(pos, h, s, b, a)  // gradient stop
color.mix(c1, c2, t)         // interpolate colors

// Vectors
vec3(x, y, z)                // create vector
vec.add(a, b)
vec.sub(a, b)
vec.mul(a, scalar)
vec.div(a, scalar)
vec.dot(a, b)
vec.cross(a, b)
vec.length(a)
vec.normalize(a)
vec.lerp(a, b, t)
vec.distance(a, b)
```

### Preset Functions:

```javascript
loadPreset("smooth");    // smooth, sparkle, ribbon, helix, neon, rain
presets.sparkle();       // call preset directly
```

### Example Scripts:

**Rainbow Helix:**
```javascript
brush.geometry.baseSize = 0.01;
brush.stroke.jitter = 0.2;
brush.color.mode = "rainbow";
brush.color.hueShift = 3.0;
brush.physics.gravity = [0, -0.005, 0];

brush.onPoint = function(ctx) {
    var angle = ctx.index * 0.3;
    return {
        offset: [Math.cos(angle) * 0.02, 0, Math.sin(angle) * 0.02]
    };
};
```

**Pulsing Size:**
```javascript
brush.geometry.baseSize = 0.015;
brush.onPoint = function(ctx) {
    return {
        size: 0.01 + 0.01 * Math.sin(ctx.index * 0.5)
    };
};
```

**Noise-based Scatter:**
```javascript
brush.geometry.baseSize = 0.008;
brush.onPoint = function(ctx) {
    var n = math.noise3d(ctx.position[0]*10, ctx.position[1]*10, ctx.position[2]*10);
    return {
        offset: [n * 0.02, n * 0.02, n * 0.02],
        hue: n * 0.5 + 0.5
    };
};
```



---

## 2025-02-09 – Session 7: UI Cleanup & MIDI Fix

### ✅ COMPLETED: Build Error Fixes
- **MIDINetworkManager.swift** and **MIDISettingsView.swift** were on disk but missing from pbxproj
- Added both files to PBXBuildFile, PBXFileReference, PBXGroup, and PBXSourcesBuildPhase sections
- Added missing `midiSettingsModal` computed property to ContentView
- Fixed `MIDINetworkSession.destinations()` compile error — replaced with `MIDIGetDestination()` loop

### ✅ COMPLETED: UI Cleanup
- **Removed debug text** from GyroAR3DPaintApp.swift (DEBUG labels and print statements)
- **Removed White Room mode** from AppMode enum and ModeSelectionView
- **Added back-to-menu button** (house icon) in ContentView's left status icons
  - Uses same glass-circle style as other status buttons
  - `onExitToMenu` closure passed from GyroAR3DPaintApp
- **Brush Studio: Script editor moved** from top-level tab to overlay
  - Accessible via `</>` button in header bar
  - Opens as full overlay with editor, run button, examples
  - Default tab is now Presets instead of Script
- **Brush Studio: Test canvas removed** from right panel
  - Studio is now full-width parameter view
  - Bottom bar has Reset / Save As controls

### Files Modified:
- `GyroAR3DPaintApp.swift` – Removed debug, updated ContentView init
- `ModeSelectionView.swift` – Removed virtualGallery case
- `ContentView.swift` – Added onExitToMenu, home button, midiSettingsModal
- `BrushStudioMode.swift` – Restructured layout, script overlay, removed test canvas
- `MIDINetworkManager.swift` – Fixed destinations() API usage
- `project.pbxproj` – Added MIDI files to build



---

## 2025-02-09 – Session 7b: Drawing Distance Slider

### ✅ COMPLETED: Drawing Distance Control

**Feature:** Left-side slider now has two modes — Opacity and Distance

**How it works:**
- Left edge slider toggles between opacity (default) and drawing distance mode
- Small button at bottom of slider switches mode (circle icon ↔ sparkle arrows icon)
- **Opacity mode** (white): Same as before, 0-100%
- **Distance mode** (cyan): Controls how far from camera the brush paints
  - Bottom (0): Default distance (0.3m from camera)
  - Top (100%): 2.3m from camera (+2m extra)
  - Logarithmic curve: `2.0 * log(1 + t*9) / log(10)` — fine control at close range, bigger jumps at distance
  - Label shows actual distance in meters (e.g. "0.3m", "1.2m", "2.3m")

**Technical:**
- `DrawingEngine.drawingDistanceOffset` — new @Published Float (0-1)
- `ARViewContainer.getBrushPosition()` — applies logarithmic distance offset to camera forward vector
- `ContentView.LeftSliderMode` enum — switches between `.opacity` and `.distance`
- Slider track color changes: white for opacity, cyan for distance

### Files Modified:
- `DrawingEngine.swift` – Added `drawingDistanceOffset` property
- `ARViewContainer.swift` – Modified `getBrushPosition()` with logarithmic distance calc
- `ContentView.swift` – Dual-mode left slider with toggle button

