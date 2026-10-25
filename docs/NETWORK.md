# Multiplayer foundation

The product flow follows racinggame: Host by Code / Join by Code, a foreground
host authority, Ready/Start, role assignment and rematches. The shared short-code
service resolves identity only; Iroh transports encrypted QUIC traffic directly
or through its relay. No public server deployment is implied.

## Transport provenance

`crates/curl-transport` derives from the user's racinggame native Iroh adapter,
itself derived from tipragot/godot-iroh commit
`153979fc02f86b10802358ae38fb74204fbf179a`. The upstream MIT license is retained
in `licenses/godot-iroh-MIT.txt` and included in exports. Project-specific ALPN is
`pebble-granite/iroh/1`; JNI application-context initialization uses PebbleMobile.

The inherited adapter bounds peer count, receive/send queues and packet sizes,
uses a lazy two-worker Tokio runtime, supports connect cancellation, and keeps
Godot calls off worker threads. No racing gameplay logic is imported.

The separate Rust match authority validates releases and sweep ownership and
replays late accepted inputs. Transport peers are not player seats; the host must
bind each connection to a seat before interpreting any gameplay command.

## Current scope

The playable scene currently provides local practice and mixed doubles. Online
gameplay and room UI are under construction. Android includes a small Godot plugin supplying a JNI application context before
Iroh starts; its new Gradle export still requires CI and installed-device validation. Public relay availability remains an
external service dependency. No host migration is planned for the first slice.

## Validation

`GODOT_BIN=godot python3 tools/godot.py --headless --path . --script tests/transport.gd`
checks four bidirectional channels, connection cancellation, and forced disconnect.
Add `-- --relay-only` to prove relay routing. Both passed locally on macOS ARM64.
These probes require external relay/discovery service availability and are separate
from deterministic offline release gates. No two-device internet test is claimed.

## Room authority contract

`curl-match::room` binds four mixed-doubles seats to transport-authenticated
endpoint identities. The host supplies those identities from Iroh's connection
metadata, never from a client claim. Peer 1 is reserved for the original host.
The room checks model/protocol/rules compatibility before admitting a peer.

All four seats must be connected and ready before the host starts. Gameplay
commands contain no seat field; the room derives team and role from the binding.
Packets have a 1200-byte boundary and strict tagged decoding. A 128-command
receive window rejects repeats while admitting reordered sweep inputs. Each
rematch advances an epoch and requires fresh readiness.

A disconnected active-game seat remains reserved. Simulation and thinking clocks
pause until its authenticated identity returns and confirms the matching full
state hash. This hash covers simulation, rules/clocks, release snapshot and pending
sweeps. The host does not migrate. This is the authority contract only: replay
transfer, durable endpoint identity, reconnect UI and transport wiring are still
required before reconnect can be advertised as a working game feature.

## Live control-plane probes

`tests/online_lobby.gd` creates a host and three real Iroh clients, verifies roster,
ready/start, reserved disconnected seat, pause and host loss. It also exercises a
burst of readiness changes. Run with `-- --relay-only` for relay routing.
`tests/room_code.gd` registers one short code, resolves its compatible host endpoint,
and revokes it. Both probes passed locally; neither is a cross-device gameplay test.

The native codec rejects unknown fields, oversized packets, malformed UTF-8,
duplicate peer IDs, malformed hashes and control characters in rejection messages.
GDScript receives only decoded canonical lobby records. Pending handshakes and
send queues are bounded; state updates coalesce separately for each peer.
