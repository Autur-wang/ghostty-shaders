# ghostty-shaders

A three-layer custom-shader stack for the [Ghostty](https://ghostty.org) terminal:
a full-screen **starfield**, a gravitational-lensing **black hole** that bends your
terminal text around it, and a meteor-trail **cursor**. The three run as a
post-processing **chain** — declaration order *is* compositing order, each shader
receives the previous one's output as its background.

> Ghostty applies multiple `custom-shader` lines in sequence: shader N reads
> shader N−1's result via `iChannel0`. So you can't drop one file in isolation
> and expect the same look — the order below matters.
![Uploading image.png…]()

## Layers

| # | File | What it does |
|---|------|--------------|
| 1 | `shaders/starfield.glsl` | Full-screen stars: a warping "flight" layer plus a static field that keeps the whole screen covered through every animation phase. Additively blended over the terminal. |
| 2 | `shaders/blackhole.glsl` | A floating black hole. Weak-field gravitational lensing bends/magnifies the text and the starfield around an event-horizon shadow, with a photon ring and a Doppler-beamed accretion disk. Has a Pomodoro mood: swells before the hour, shrinks on breaks, fades when you stop typing. |
| 3 | `shaders/cursor_blaze.glsl` | A comet-trail cursor. Placed last so the trail isn't bent by the lens. |

## Install

1. Clone this repo somewhere stable:

   ```sh
   git clone https://github.com/Autur-wang/ghostty-shaders.git ~/ghostty-shaders
   ```

2. Add the lines from [`config.snippet`](./config.snippet) to your
   `~/.config/ghostty/config`, replacing the placeholder paths with the **absolute**
   path to this repo's `shaders/` directory (Ghostty does **not** expand `~`):

   ```
   custom-shader = /Users/you/ghostty-shaders/shaders/starfield.glsl
   custom-shader = /Users/you/ghostty-shaders/shaders/blackhole.glsl
   custom-shader = /Users/you/ghostty-shaders/shaders/cursor_blaze.glsl
   custom-shader-animation = true
   ```

3. Reload Ghostty config (`cmd+shift+,` on macOS) or restart the terminal.

### Mix and match

Each shader is self-contained — comment out any `custom-shader` line to drop that
layer. If you only want the cursor, keep just `cursor_blaze.glsl`. Per-shader
tunables (hole radius, lens strength, star density, …) live as `const` blocks at
the top of each file.

## Credits

- **starfield.glsl** — custom two-layer field.
- **blackhole.glsl** — ported from [`s0xDk/ghostty-blackhole`](https://github.com/s0xDk),
  visual approach inspired by Eric Bruneton's
  [*Real-time High-Quality Rendering of Non-Rotating Black Holes*](https://ebruneton.github.io/black_hole_shader/).
- **cursor_blaze.glsl** — from [`0xhckr/ghostty-shaders`](https://github.com/0xhckr),
  based on [chardskarth's gist](https://gist.github.com/chardskarth/95874c54e29da6b5a36ab7b50ae2d088)
  and Inigo Quilez's [2D distance functions](https://iquilezles.org/articles/distfunctions2d/).

All shaders are ShaderToy-style fragment shaders (`mainImage(out vec4, in vec2)`)
driven by the standard `iTime` / `iResolution` / `iChannel0` uniforms Ghostty provides.
