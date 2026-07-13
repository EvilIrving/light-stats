# Status Bar Fan Core Animation Validation

Status: Deferred prototype; do not implement on the current branch.

## Problem

When the menu-bar fan item is enabled, `StatusBarView` advances `fanAngle` with a
`CADisplayLink` and calls `renderAndApply()` for every animation frame. This rebuilds
and reassigns the complete template image, including all metric text, labels, network
values, separators, logo, and fan symbol.

A Debug runtime sample with the fan enabled measured approximately 45-57% CPU and
132 MB physical footprint. The dominant stack was `StatusBarView.renderImage()` and
`StatusBarView.drawFan(in:)`. The popover mesh and its hit-testing fallback were minor
in that sample.

## Proposed Direction

Keep the existing `NSStatusBarButton.image` as the static template image for all
non-animated content. Continue rebuilding it only when monitored values or enabled
items change. Preserve the existing 22-point fan slot, but leave that slot transparent
in the static image.

Place one noninteractive fan overlay at the exact center of the reserved slot. Animate
only its `transform.rotation.z` with Core Animation so the render server performs the
rotation without a per-frame Swift callback. Remove the fan `CADisplayLink`, per-frame
`fanAngle` updates, and per-frame calls to `renderAndApply()`.

The existing visual speed contract must remain unchanged:

```text
revolutionsPerSecond = min(Double(rpm) / 5000, 1) * 3
durationPerRevolution = 1 / revolutionsPerSecond
```

`nil` or zero RPM shows a static fan. Positive RPM rotates clockwise. Changes between
zero and positive RPM, and changes between positive RPM values, must preserve the
current presentation angle without a visible jump.

## Decisions

### Adopt for the prototype

- Static status text remains in `button.image` and retains the existing template-image
  rendering path, dimensions, typography, separators, and dynamic menu-bar tint.
- The fan uses one independent layer-backed overlay and one linear, repeating Core
  Animation rotation.
- RPM changes capture the presentation-layer angle, commit it to the model layer,
  remove the old animation, and start a new animation from that angle.
- The overlay returns `nil` from hit testing so every point in the status item continues
  to activate the underlying `NSStatusBarButton`.
- The overlay is decorative and must not become an accessibility element.
- Hiding the fan removes or hides the overlay and stops its animation completely.
- Geometry is derived from the same `displayItems` layout used by the static image.
- The implementation must handle sleep/wake, backing-scale changes, status-item width
  changes, and menu-bar migration between displays.

### Do not adopt without proof

- Do not use the physical `rpm / 60` rotation formula. It violates the current capped
  visual mapping and would rotate far too quickly.
- Do not add `NSVisualEffectView(material: .sidebar)` based only on the DeepSeek review.
  It is not proven to match `NSStatusBarButton.image` template tint and may introduce a
  visible material patch.
- Do not assume a child `NSImageView` receives the same wallpaper-aware menu-bar tint as
  `button.image`. This requires runtime screenshot comparison.
- Do not use private AppKit or SwiftUI APIs.
- Do not reintroduce full-image bitmap caching, animation frame-rate caps, or any design
  that still assigns `button.image` on animation frames.
- Do not change metric polling frequency, menu-bar item widths, font metrics, fan size,
  click behavior, or the existing RPM-to-visual-speed mapping.

## Prototype Branch

Create a dedicated branch from a clean baseline after the current popover hit-testing
work is settled:

```bash
git switch -c codex/status-bar-fan-layer-validation
```

Keep the prototype scoped to `StatusBarView.swift` unless a small dedicated overlay
view file is required to satisfy the one-type-per-file convention.

## Validation Plan

### Establish the baseline

Build and launch the same Debug configuration on the same Mac. Enable the fan and keep
the same status items visible. Record a 30-second CPU sample, physical footprint, Energy
Log, and a Time Profiler trace. Save screenshots at 1x and 2x backing scales.

### Validate tint before animation

Implement only the static fan overlay first. Compare it against the existing fan drawn
inside `button.image` on light, dark, and wallpaper-tinted menu bars. Test both active
and inactive menu-bar states when applicable.

Reject the overlay approach if the fan tint differs visibly from the static metrics. Do
not compensate with a hard-coded black, white, label, or control-text color. Evaluate a
public-API mask or template rendering approach before considering a visual-effect view.

### Validate geometry and sharpness

Test every status-item toggle combination with the fan at the beginning, middle, and end
of the item sequence. Confirm the fan remains 14 points, centered in the 22-point slot,
and pixel-aligned with no clipping or horizontal shift.

Move the menu bar between 1x and 2x displays and change the primary display. Confirm the
overlay updates its frame and `contentsScale` and remains as sharp as the existing SF
Symbol rendering.

### Validate animation continuity

Exercise these transitions repeatedly:

```text
nil -> 0 -> 1000 -> 3000 -> 5000 -> 3000 -> 1000 -> 0 -> nil
```

Confirm clockwise rotation, the existing capped speed, no angle snap, no flash, and no
pause at the repeat boundary. Repeat after display sleep/wake and after changing the
primary display.

### Validate interaction and accessibility

Click the fan slot, its edges, every adjacent metric, and the separators. Every click
must toggle the popover exactly as before. Hover, right-click, and panel auto-dismiss
behavior must remain unchanged.

With VoiceOver enabled, confirm the status item remains one coherent accessible control
and the decorative fan overlay creates no additional focus stop or announcement. Check
the system Reduce Motion setting and decide whether to freeze the fan only if doing so
matches the app's existing animation policy.

### Validate performance

Repeat the baseline 30-second profiling run with identical settings. The following
conditions are required:

- `StatusBarView.renderImage()` and SF Symbol rasterization no longer appear on animation
  frames.
- No `CADisplayLink` remains for the menu-bar fan.
- CPU use with the fan enabled is within 5 percentage points of the same configuration
  with the fan disabled, excluding normal monitor sampling spikes.
- Physical footprint does not grow continuously over 50 fan enable/disable cycles.
- Core Animation performs only the fan transform; static metric layers are not redrawn
  for animation.

## Merge Gate

Merge only when the overlay is visually indistinguishable from the existing fan across
tested menu-bar appearances and displays, interaction and accessibility remain unchanged,
all animation transitions are continuous, and the performance requirements pass.

If public APIs cannot reproduce the exact template tint, retain the current renderer and
leave this optimization deferred rather than accepting a UI mismatch.

## Review Notes

DeepSeek agreed that separating static status content from a Core Animation fan can
remove the dominant per-frame CPU work. Its warnings about overlay hit testing, speed
change continuity, backing-scale changes, sleep/wake, and accessibility are incorporated
above.

DeepSeek's recommendations to use `NSVisualEffectView(.sidebar)` and a physical RPM
formula are not accepted. Both conflict with the required visual and behavioral contract
unless independently proven by the prototype.
