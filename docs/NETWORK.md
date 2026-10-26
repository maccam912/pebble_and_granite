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

The playable scene provides local practice/mixed doubles and an experimental
online room/match interface. Full cross-device match validation remains open. Android includes a small Godot plugin supplying a JNI application context before
Iroh starts; Build 14 passed export CI and installed Android-emulator golden/JNI checks. Public relay availability remains an
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
cross-device and full-match testing are still
required before reconnect can be advertised as a finished game feature.

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

## Local player identity

Online clients persist their Iroh signing key at `user://network/player.key`.
The native adapter creates it exclusively with owner-only Unix permissions and
flushes it before connecting; it never sends the secret through Godot or room
packets. Existing malformed/unreadable keys fail closed instead of silently
creating a new identity. Low-level transport probes can request ephemeral keys;
multi-client tests use isolated files and remove only their own test keys.

Reconnecting uses the same authenticated endpoint identity and reclaims the
reserved seat. The room remains paused until replay synchronization is verified.
This is not yet a complete reconnect gameplay flow. Hosts remain ephemeral and
host loss ends the room; host migration is explicitly out of scope.

## Authoritative replication contract (protocol 6)

Room gameplay now runs through the same recorded match used by local saves. Each
accepted update carries an epoch, monotonically increasing revision, before/after
full-state hashes and validated input records. The bounded host queue must be
drained by the network loop. Replicas reject gaps, duplicates, old epochs and hash
mismatches atomically. Live batches permit at most 24 physics ticks or 1000 ms of
thinking; settling emits only the ticks actually simulated.

Reconnect journals use ordered 1028-byte-or-smaller `PGS1` packets with epoch,
revision, total size, offset and whole-transfer checksum. The receiver accepts at
most 16 MiB, rejects missing/duplicate/mixed chunks, and verifies the journal by
replaying the authoritative core before replacing a replica. The transport layer
must impose a transfer deadline and accept these packets only from its host.
The checksum detects corruption; authenticated Iroh supplies peer authenticity.

`tests/replica.gd` exercises the native bridge offline and is a desktop CI gate.
Core tests cover a full shot, late sweeps on both sides of an in-flight restore,
malformed updates and chunk-transfer failures. The network loop routes these packets on reliable channels 1 and 2, with
control on channel 0. Start/reconnect freezes play until exact epoch/revision/hash
acknowledgement; transfers expire after 60 seconds. A four-peer live test covers
placement, a complete shot and in-flight reconnect under default/relay routing.
The scene exposes room UI, shared presentation frames and seat-restricted online input. Restore remains synchronous and live updates currently copy/trial state;
measure Android cost before shipping long-match reconnect as finished.

## Journal storage

Match format 2 stores immutable, independently compressed blocks of 256 input
records plus an active tail. Blocks use pinned pure-Rust zlib compression and
base64 encoding inside JSON. Loading bounds each expansion to 128 KiB and replays
all records through the authority. Format 1 remains readable for existing saves.
Whole archives remain limited to 16 MiB; decoded records and flight ticks are
bounded separately at 2 million and 4 million. Immutable blocks are shared across
transactional state copies. The 80-throw/two-brush/60-Hz capacity fixture measures
5.42 MB for 432,001 records; it is a storage test, not a full online game test.

Protocol 5 brush spans cover up to twelve simulation ticks per input sample. The
host retimes an obsolete span's start once and preserves its duration, validates
all ticks atomically, and resimulates once. Defending spans never predate receipt
and tee authorization. This is continuous hold sweeping; spatial brush strokes,
latency feel and Android performance are not yet approved. Room controls keep the
host simulation running while its lobby is visible; application stalls/background
suspension still need explicit user-facing handling and device validation.

The full `online_room_flow.gd -- --full-match` probe passed through nine ends and
four-player rematch readiness on local Iroh endpoints, using actual room-code UI
operations. Physical cross-device play remains unverified. Protocol 6 rejects
brush timestamps predating the current release, including before defending-span
retiming. Normal stale brush arrivals after settlement are consumed without a
user-facing rejection; they cannot mutate the match. A bounded derived rewind
cache now accelerates accepted late spans without changing canonical state.
