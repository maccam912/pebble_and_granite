# Physics measurement and calibration

The current model is provisional. The repository now has a repeatable comparison
pipeline, but no measured reference dataset has been accepted. Synthetic fixtures
and deterministic replay traces cannot establish real-ice accuracy. No physics
coefficients were changed during this checkpoint.

## Run the baseline

```sh
cargo build --locked --release -p curl-server
python3 tools/physics_calibration.py validation/calibration/baseline.json \
  --output build/physics-baseline.json
```

The tool uses the native replay engine, with its standard release origin,
uniform fresh ice, and explicitly specified velocity and rotation. It records
model version, binary and manifest SHA-256, and each exact replay/state hash.
It checks the binary's model version against the checkout before running.

Model 3 baseline, measured from its simulated release to the end of motion:

| Case | Downrange | Signed curl | Duration | Signed rotations |
| --- | ---: | ---: | ---: | ---: |
| Guard, 1.980 m/s, 0.120 rev/s | 25.548 m | +0.861 m | 23.675 s | +2.685 |
| Draw, 2.085 m/s, 0.060 rev/s | 28.567 m | +0.960 m | 25.167 s | +1.422 |
| Draw, 2.085 m/s, 0.120 rev/s | 28.569 m | +0.935 m | 25.167 s | +2.844 |
| Draw, 2.085 m/s, 0.250 rev/s | 28.577 m | +0.838 m | 25.167 s | +5.926 |
| Opposite turn, −0.120 rev/s | 28.569 m | −0.935 m | 25.167 s | −2.844 |
| Same standard draw, first 7 s swept | 29.194 m | +0.892 m | 25.504 s | +2.880 |

These numbers characterize the simulation; they are not real measurements.
The baseline also includes a slow segment and a heavy shot that exits the sheet.
An exit is marked `truncated` and cannot pass a stopping-point comparison.
A short stone that stops before the hog line still has a complete physical path.

## Supply measurements

Copy the baseline manifest and replace cases with independently measured data.
The schema accepts only straight initial velocity components, initial rotation,
and optional centered sweeping. Contact/obstacle setups are rejected rather than
silently ignored; they need a separate contact experiment.

Each case needs an `id`, `release`, and `source`. Release units are explicit:
`vx_mm_s`, `vy_mm_s`, `spin_milli_rps` (1 revolution/s = 1000, **not radians/s**).
Positive rotation and curl are toward the thrower's right. The initial position
is translated to the model release origin, so compare displacement from the
measurement's initial frame, not absolute rink coordinates. Keep the initial
velocity direction in the recorded coordinate frame.

Measured sources must include `kind: "measured"`, a `reference` identifying the
source/session/shot, a `method` describing the measurement and uncertainty, and
`conditions` describing the stone, ice, sweep state and initial-frame convention.
Do not mark a model-generated result as measured.

Put any observed metrics in `observed`, and supply matching positive absolute
uncertainties/acceptance limits in `tolerance`:

| Metric | Definition |
| --- | --- |
| `downrange_mm` | Final displacement projected along the initial velocity |
| `curl_mm` | Signed final displacement perpendicular to that velocity |
| `duration_ms` | Time from the initial measurement frame to rest |
| `turns_milli` | Signed accumulated revolutions × 1000 over that interval |

Optional `sweep` is `{ "start_tick": 0, "end_tick": 1680, "effort": 255 }` for
the first seven seconds at 240 Hz, end exclusive. This specifies a model input,
not a conversion from measured brush force. Keep sweeping calibration separate
until a defensible effort/force correspondence is established. A sweep interval
extending beyond the shot is rejected by the native replay validator.

```sh
python3 tools/physics_calibration.py path/to/measured-shots.json \
  --output build/measured-comparison.json --check
```

The report includes each residual and tolerance, plus bias/RMSE across supplied
untruncated measured cases. `--check` exits 0 only when there is at least one
measured case and all measured cases satisfy their supplied tolerances. It exits
1 for a mismatch and 2 for missing measurements or invalid inputs. Baseline or
synthetic cases can never certify calibration. A matching small dataset is only
evidence for those conditions, not general approval of the physics.

## Fit and validate a future change

Collect repeated unswept draws across speeds, both turns and rotation rates.
Keep uncertainty estimates, stone identity and ice conditions with each shot.
Use separate held-out shots to assess a fitted parameter change. Then add
independent sweep and contact experiments; do not compensate one mismatch by
changing an unrelated coefficient. Record the before/after residuals and limits.

Current model parameters live in `crates/curl-sim/src/lib.rs`. A retained physics
change must bump the model version, preserve or explicitly migrate existing
journals, regenerate intentional golden traces, and pass core/native checks.
Human curler judgement, physical-device input feel, and measured ice accuracy
remain different validation gates.

Primary research starting points include the
[2022 precision kinematic study](https://www.nature.com/articles/s41598-022-19303-4)
and the [2020 stone surface study](https://pmc.ncbi.nlm.nih.gov/articles/PMC7692518/).
No raw observations from those papers have been imported or treated as an
accepted calibration dataset in this repository.
