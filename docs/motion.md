# Motion guide for Dot

The rules every animation in Dot follows. The dot is the product, so motion is how it shows character.

## 1. The one rule: alive, but calm

Dot is used by people who are typing and thinking. Motion that pulls the eye while you type is a bug.

- Still while you type. Motion happens at moments of change, never as decoration.
- Idle "breathing", if any, stays under the attention threshold: about 3–5% scale, period 3–5 s, never a hard on/off blink.
- One thing moves at a time. Two moving things fight for attention.
- Reduce Motion: every animation becomes a short cross-fade (about 0.15 s). Meaning stays; movement goes.

## 2. Timing (how long)

| Moment | Duration | Why |
|---|---|---|
| Direct response (press, hover) | 0.08–0.15 s | Under ~100 ms reads as "instant", as if the hand did it |
| State change (color, count) | 0.2–0.3 s | Noticed, but doesn't make you wait |
| Enter / exit | 0.25–0.4 s enter, ~70% of that to exit | Leaving should feel lighter than arriving |
| Ambient (breathing, thinking) | 1.2–5 s cycles | Slow enough to read as "living", not "alarm" |

Exits are faster than entrances. Feedback to a click starts on mouse-down, not mouse-up.

## 3. Springs, not curves

Use springs for anything that moves or scales, the way Apple's own UI does (WWDC23 "Animate with springs"):

- Two numbers: perceptual duration and bounce (-1 to 1).
- Bounce 0: smooth, no overshoot. Use for color and fades that ride on scale.
- Bounce ~0.15: barely felt; reads as "physical". The default for Dot.
- Bounce ~0.3: visibly playful. Only for rare, happy moments (all fixed).
- Above 0.4: cartoon. Never.
- Core Animation: `CASpringAnimation(perceptualDuration:bounce:)`.

Every animation must be interruptible: start the new one from the current on-screen value (the presentation layer), never jump back to a start value.

## 4. The animation principles, sized for a 9 pt dot

| Principle | In Dot |
|---|---|
| Squash and stretch | 5–10% at most. A press squashes to ~0.9 and the dot widens slightly; it never becomes a cartoon blob. |
| Anticipation | A 20–40 ms dip before a big action (opening the menu, applying all fixes). |
| Follow-through | Overshoot 2–5% then settle. A ring or ripple keeps going after the dot stops. |
| Slow in / slow out | Comes for free with springs. |
| Arcs | When the dot travels (to a new input), it moves along a gentle arc, not a straight line. |
| Secondary action | Small extras that confirm the main action: a ring, a tick, a soft glow. Never louder than the main action. |
| Staging | The dot never animates where the eye isn't expected; no surprise motion away from the caret. |
| Exaggeration | Reserved for rare moments (everything fixed). Daily moments stay quiet. |
| Appeal | A perfect circle, soft edges, color from the system palette, consistent personality across states. |

## 5. What makes something feel alive

- It reacts to you. Response to hover, press and typing within one frame.
- It has moods. Different states move differently (thinking ≠ waiting ≠ done), not just different colors.
- It isn't a metronome. Living things vary slightly; tiny randomness in timing (±10%) beats a perfect loop.
- It has weight. Springs, not linear tweens; it settles instead of stopping.
- It remembers. A state change animates from where it was, not from scratch.
- It rests. Stillness makes the moments of motion mean something.

## 6. Implementation rules (macOS)

- Animate only `transform`, `opacity` and colors on layers (GPU, smooth at 120 Hz ProMotion). No `draw(_:)` redraws per frame.
- Shapes are `CAShapeLayer`s; glows are `shadowPath` + `shadowRadius` or a blurred sublayer, not images.
- Procedural motion (anything that isn't a fixed curve) runs on `CADisplayLink` (macOS 14+), stopped whenever the dot is hidden.
- Respect `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` at the moment of animating, not once at launch.
- Zero CPU when idle and hidden. An always-on loop is a battery bug.

## Sources

- Apple, WWDC23 "Animate with springs" (duration and bounce, bounce ~0.15 vs ~0.3): https://developer.apple.com/videos/play/wwdc2023/10158/
- Apple, WWDC18 "Designing Fluid Interfaces" (responsive, interruptible, redirectable), summarized: https://medium.com/@nathangitter/building-fluid-interfaces-ios-swift-9732bb934bf5
- The 12 principles adapted to UI: https://uiux-atlas.pages.dev/lessons/motion/the-12-principles-of-animation-adapted-to-ui
- Squash and stretch in UI: https://joshwcomeau.com/animation/squash-and-stretch
