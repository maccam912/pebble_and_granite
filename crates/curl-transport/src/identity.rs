//! Local reconnect identity. Never serialize the private key into room packets.
use std::fs::{self, OpenOptions};
use std::io::{Read, Write};
use std::path::Path;

use anyhow::{Context, Result, ensure};
use iroh::SecretKey;

pub fn load_or_create(path: &Path) -> Result<SecretKey> {
    ensure!(path.is_absolute(), "Identity path must be absolute");
    let parent = path.parent().context("Missing identity directory")?;
    fs::create_dir_all(parent).context("Cannot create identity directory")?;
    let mut options = OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    match options.open(path) {
        Ok(mut file) => {
            let key = SecretKey::generate();
            file.write_all(&key.to_bytes())
                .context("Cannot write identity")?;
            file.sync_all().context("Cannot persist identity")?;
            Ok(key)
        }
        Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => {
            // Exact length, bounded read. Interrupted/corrupt saves fail closed.
            // Never replace an existing identity: it owns a reserved match seat.
            let mut bytes = Vec::new();
            fs::File::open(path)
                .context("Cannot read identity")?
                .take(33)
                .read_to_end(&mut bytes)?;
            let bytes: [u8; 32] = bytes
                .try_into()
                .map_err(|_| anyhow::anyhow!("Invalid identity file"))?;
            Ok(SecretKey::from_bytes(&bytes))
        }
        Err(error) => Err(error).context("Cannot create identity"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn persists_and_never_replaces_invalid_identity() {
        let directory =
            std::env::temp_dir().join(format!("pebble-identity-{}", std::process::id()));
        fs::create_dir_all(&directory).unwrap();
        let path = directory.join("player.key");
        let first = load_or_create(&path).unwrap();
        assert_eq!(first.public(), load_or_create(&path).unwrap().public());
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            assert_eq!(
                fs::metadata(&path).unwrap().permissions().mode() & 0o777,
                0o600
            );
        }
        fs::write(&path, [1, 2, 3]).unwrap();
        assert!(load_or_create(&path).is_err());
        assert_eq!(fs::read(&path).unwrap(), [1, 2, 3]);
        assert!(load_or_create(Path::new("relative.key")).is_err());
        fs::remove_dir_all(directory).unwrap();
    }
}
