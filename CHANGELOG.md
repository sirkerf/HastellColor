# Revision history for HastellColor

## Unreleased — macOS / iPadOS drawing prototype

- Build for Mac Catalyst (Apple silicon and Intel); enable mouse input and use
  an app-specific autosave directory on macOS.
- Add print, screen, and comic paper presets with mm/px/dpi, orientation,
  custom dimensions, and a bounded A4/600 dpi canvas.
- Add paper color with undo/redo, and pigment strength generated from Haskell.
  Archive v2 migrates v1 without changing old strokes.
- Preserve paper tint and print resolution in 16-bit P3 PNG; reduce export
  memory by converting directly from GPU readback into the output buffer.

- Support 13-inch iPad layouts and expose a labeled color chooser with Display P3
  RGB controls at 1024 levels per channel, without 8-bit conversion.

- Add an iPadOS Swift/Metal studio with Pencil pressure/tilt, colors, eraser,
  undo/redo, autosave, editable archives, and 16-bit Display P3 PNG export.
- Share Haskell material equations with generated Metal functions and verify
  the GPU against CPU reference fixtures.

## 0.1.0.0 -- YYYY-mm-dd

* First version. Released on an unsuspecting world.
