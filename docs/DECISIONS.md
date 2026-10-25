# Foundation decisions — 25 October 2026

The design bible is the product specification. This file records implementation
decisions and discrepancies without silently rewriting it.

1. **Authority:** Q32.32 Rust at 240 Hz owns stones, ice, rules, accepted inputs,
   and replay hashes. No Godot rigid bodies or floating-point simulation fallback.
   Godot is the input/presentation shell. Native server shares the same core.
2. **Platforms:** Windows x64, Linux x64, macOS ARM64/x64, Android ARM64 initially.
   Android x64 is useful for emulator verification. iOS, web packaging, consoles,
   gamepads and VR are deferred. A portable core can still be checked on wasm.
3. **Toolchain:** Godot 4.7 stable (installed `5b4e0cb0f`, official archive verified),
   Rust 1.98.1, gdext 0.5.5. Pin exact dependencies in Cargo.lock. The bible's
   third-party claim of 4.7.2 is not a build dependency.
4. **Coordinates:** metres; far tee at (0,0), delivery travels in +y; near hog
   y=-28.349, far hog y=-6.401, far back line y=1.829, side lines x=±2.375.
   Clockwise spin is positive and curls toward +x. Radius 0.142 m. Constants
   derive from the bible's 34.750 m tee separation, not the trainer's -28.346.
5. **Reference reuse:** curling_trainer is floating point at 250 Hz. Reuse model
   ideas, diagnostic conventions and test scenarios, not its state ABI. Its
   scatter, contact coefficients and wear effects remain provisional calibration.
6. **Networking:** racinggame currently prefers Iroh Host/Join by four-character
   code, with foreground host authority, readiness and rematches. Preserve that
   product flow. Transport carries bounded versioned commands, never trusted
   client positions. Do not couple curl-sim to Iroh, Godot or room discovery.
7. **Input honesty:** physical mouse/trackpad motion cannot be inferred exactly
   from OS pointer pixels. Normalize viewport coordinates, calibrate per device,
   retain timestamped events, then resample at ticks. Zero-order-held render-frame
   samples cannot promise identical 30/144 Hz results; test identical event streams
   under different render scheduling instead. No hidden human release noise at
   this stage; report any eventual skill-dependent noise explicitly.
8. **Compatibility:** sim version, wire version and replay schema are independent.
   Canonical hashing uses explicit little-endian bytes, never Rust memory layout,
   platform hashers or unordered collections. Snapshots include evolving ice.
9. **Roadmap gate:** exported bible contains missing embedded roadmap diagrams.
   Implement foundations → playable feel lab → measured input/sweep iteration →
   casual mixed doubles → broader modes. Human curler approval is still required
   for the feel gate; automated tests cannot approve it. Build infrastructure and
   architectural proofs early without claiming later product phases are complete.

Reference projects are read-only during this work. Development releases are
prereleases; store signing, public service deployment and physical-device feel
are separate owner follow-ups.

