# Dock click collapse

Verified on macOS 27.0.1 (build 26A434), 2026-10-11, on a 3008×1692 pt display with an auto-hidden
Dock (`autohide = 1`, `magnification = 1`, `tilesize = 34`).

## What the gesture is

macOS activates a non-frontmost application when its Dock icon is clicked, and brings a minimized
window back on that same click. Clicking the *frontmost* application's icon does nothing. That one
missing direction is the whole feature: `DockClickService` puts the frontmost application's windows
away, and the next click on the same icon puts them back. It is not a duplicate of anything the
system already does, which is also why the decision is asymmetric rather than "toggle windows"
(`DockClickPolicy`).

## Detection

An `NSEvent` global monitor, not an event tap: a passive monitor needs no permission of its own,
cannot swallow an event, and is delivered on the main thread, where every decision is made. Only the
Accessibility half — resolving the icon and reading the application's window facts — runs on
`AXCommandQueue`.

Every fact a click is judged on is captured *before* the mouse goes down, because the Dock changes
the world while it handles the click: whether the application was frontmost and whether it was
showing windows cannot be recovered afterwards.

A click stays a click only if the button comes up within 6 pt of where it went down and within 0.6 s;
that is what separates it from a Dock-icon drag (rearranging the Dock) and a press-and-hold (the
Dock's own menu). `DockClickGesture` is pure and clock-free, so both are unit-tested without a mouse.

## The cheap gate has to be a superset

Every mouse-down in the system reaches the monitor, so the first test is arithmetic: a click that
cannot be a Dock click must not cost an Accessibility round trip. `DockGeometry.proximityBand` is
that test, and it must be a **superset** of the Dock for two measured reasons.

An auto-hidden Dock reserves **nothing**. `NSScreen.visibleFrame` then differs from the frame by the
menu bar alone, so a band derived from that difference is zero — and a zero band rejects every click
before the Dock is ever asked anything. That is what this feature did on this machine: the service
was running, the toggle was on, and not a single click produced a journal record.

| | reserved band | revealed Dock plate | icon under the pointer |
|---|---|---|---|
| auto-hidden | 0 pt | 48 pt tall, at the screen edge | magnified 58×70 pt, ~16 pt above the plate |
| docked (for contrast) | 74 pt at 1512×982 | the band itself | — |

A magnified tile is drawn *above* the plate the Dock reports, which is the second reason the gate is
taller than the Dock: the previous gate (the reserved band plus 10 pt of slack) lost clicks on the top
of a magnified icon on a Dock that reserves space.

So the gate is `max(reserved band, 192 pt)` along the Dock's edge. A Dock tile is at most 128 pt and
the plate and magnified tile stay inside 1.5× that, and the number only decides whether a closer look
is worth it.

Being generous is safe because the gate is not the decision. The authoritative answer is the
`AXUIElementCopyElementAtPosition` hit test that follows, which resolves `AXApplicationDockItem`
correctly on macOS 27 while the Dock is showing (`AXDockItem` → `AXList` → Dock pid). A click inside
the gate that resolves to something else is ignored — recorded as `unresolvedIcon`, throttled to one
record per minute, because with an auto-hidden Dock the gate also covers the bottom of whatever window
sits against the edge and an ordinary click there is not a fault.

The same gate is used by the (currently gated-off) Dock hover preview, so the auto-hide trap is not
rebuilt there the day that surface ships.

## Acting

Minimize runs through `WindowMinimizeService` (`AXMinimized`, then the window's own `AXMinimizeButton`,
then one retry wave, because a window that is mid-animation accepts the write and stays put). The
collapsed set is remembered by title plus `ProcessIdentity`, so a reused pid cannot restore the wrong
windows. `collapsed`, `restored`, `collapseFailed`, and `restoreFailed` enter the diagnostic journal;
a restore that changed nothing is a failure, not a toggle, and drops the record so the next click
starts from the truth.

The move-exclusion list is deliberately not consulted: it exists for actions that break a media
player, and minimizing is the reversible action the yellow button performs.

Two journal entries look like silence and are on purpose. `pass` reasons are debug-only, because this
runs for every Dock click in the system and a journal that recorded ordinary clicks would hide the
faults it exists to show. `windows-away` means Accessibility reports no windows at all for an
application we collapsed — many applications stop publishing a minimized window through `AXWindows`,
and the Dock brings it back by itself on that very click — so the record has nothing left to own.
