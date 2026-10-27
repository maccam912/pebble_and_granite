# Model 3 compatibility fixtures

Captured before model 4 was implemented. The golden traces are the repository's
model-3 every-tick traces. Practice and team command journals came from installed
Android build 83, clean commit `648419c7ba2d7e83420ee5b7aea78783015cfe6c`, APK SHA256
`c00a2e3b26d4c0346422b17879cde6a88b67a1ca9acb775345ff372a11df8f14`.
They are isolated automated probe sessions, with no player preferences, identities
or personal information. The expected JSON files are the original desktop
verification output from that build's model-3 binary.

The team fixture includes Gold and Cyan deliveries and brush commands; the
practice fixture includes a takeout setup and actual Android gesture. Tests load,
resave and replay both without changing their hashes. A native test also continues
the old team match through the model-3 brush fallback and verifies another reload.
Keep these fixtures and expectations fixed when updating current golden traces.
