# mytov

Desktop apps in [Tov](https://github.com/richiemcilroy/Tov) — a port of
[mygo](https://github.com/egoist/mygo)'s native UI mode. Like mygo's
`package ui`, mytov draws the interface itself: no HTML, no JavaScript,
no webview.

Tov has no FFI, so a window is a tiny helper process. Each frame the app
lays out its view tree into a display list (rects and text runs) and
writes it as a JSON line on the helper's stdin; the helper paints it
into an `NSWindow` with AppKit/CoreText and streams input events back on
stdout. The helper source is embedded in `src/mytov.tov`, compiled to
`~/.cache/mytov` on first run, and reused until it changes.

## Status: spike

Works today (macOS only):

- `text`, `button`, `column`, `row`, `pad`, `spacer` views
- centered-stack layout, hit-tested clicks, window resize events
- `run({ title, width, height, view })` — the app exits when the last
  window closes
- `tov test` coverage for layout and hit regions
- `MYTOV_CLICK="x,y"` in the environment posts a synthetic mousedown for
  testing without a click

Not yet: every other widget, real text measurement (layout uses
estimates), keyboard/scroll/input events, high-DPI, diffed frames,
multiple windows, menus/tray/dialogs, Linux and Windows.

## Try it

Requires `tov` (build it from a clone of `richiemcilroy/Tov` with
`cargo install --path crates/tov`, or use the install script on
tov.sh) and `clang` (Xcode command line tools) for the first run.

```sh
cd examples/hello
tov run main.tov
```

## The API, so far

```ts
import { button, column, run, text } from "mytov"
import type { View } from "mytov"

class Counter { n = 0 }
const counter = new Counter()

function view(): View {
  return column([
    text(`${counter.n}`, { size: 40, bold: true }),
    button("Increment", () => { counter.n += 1 }),
  ], 12)
}

try run({ title: "Counter", width: 480, height: 360, view })
```

`view()` is re-rendered after every input event; the frame is written
to the window only when it changed.
