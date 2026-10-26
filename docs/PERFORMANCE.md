# Performance probes

Measurements below are single local probes on Apple M5 Pro/macOS with Rust 1.98.1,
Godot 4.7 and model 2. They are regression evidence, not Android or universal FPS
claims. Run native release builds when assessing shipping behavior; debug builds
perform much more slowly.

## Late brush spans

Run `cargo test --locked --release -p curl-match profile_continuous_late_sweeping -- --ignored --nocapture`.
The fixture simulates one 26.017-second shot with 520 twelve-tick brush spans, each
arriving twelve ticks late. Both implementations finished at full authority hash
`0f60680c408b6903`.

| Implementation | Entire probe CPU wall time | Slowest span |
| --- | ---: | ---: |
| Replay from release for every late span | 5,355.890 ms | 19.922 ms |
| Bounded rewind checkpoints | 83.673 ms | 0.146 ms |

The cache retains at most four immutable simulation checkpoints, spaced twelve
ticks apart, covering the 24-tick late-input window. A late update invalidates
checkpoints after its first changed tick and replays from the newest valid one.
Each checkpoint includes ice, wear, fatigue, stones and all other simulation data.
The release checkpoint remains a fallback. Immutable checkpoints are shared by
transactional authority copies. They are derived data and excluded from canonical
hashes and persisted journals. A test compares cached execution against forced
full-release replay across every accepted late offset.

## Four-view room flow

`tests/online_room_flow.gd` creates an actual short-code room, joins three Iroh
clients through the room UI, starts after readiness, places stones, and runs a
fixed release with a teammate holding the sweep button. All replicas must finish
at the host's exact hash with no rejected gameplay requests. It revokes its code
and deletes only its own test identity files. This requires external discovery,
relay and code-directory services, so it is not an offline CI gate.

With debug native libraries, the initial probe took 171.279 seconds wall time for
25.404 seconds of simulated travel and observed a 709.637 ms maximum process-frame
gap. After the rewind cache, the same debug flow took 68.620 seconds with a
268.986 ms maximum gap. These runs put four game views in one process; the latter
also overlapped core verification work. With release native libraries, the room flow took 25.446 seconds wall time for
25.404 seconds of simulated travel, with an 8.470 ms maximum process-frame gap
across 3,688 frames. This is four local views in one headless process, not a
physical-device or GPU benchmark. Neither debug result establishes acceptable
real-time gameplay.

Use `python3 tools/build_native.py --release` before the live probe. Add
`-- --full-match` to drive subsequent shots through all ends, scoring and rematch
readiness using the same fixed-step scene callback at an accelerated test cadence.
Only the first swept shot is used for real-time timing; later shots are correctness
tests. Cross-device, physical Android and long-match reconnect profiling remain open.
