//! Initial endpoint publication may lag behind sharing its identity. Retry only
//! address discovery, inside the client's overall cancellable connection deadline.
use std::{future::Future, time::Duration};

const DELAYS: [Duration; 6] = [
    Duration::from_millis(250),
    Duration::from_millis(500),
    Duration::from_secs(1),
    Duration::from_secs(2),
    Duration::from_secs(4),
    Duration::from_secs(4),
];

pub async fn discover<F, Fut, T, E>(attempt: F, recoverable: impl Fn(&E) -> bool) -> Result<T, E>
where
    F: FnMut() -> Fut,
    Fut: Future<Output = Result<T, E>>,
{
    with_delays(attempt, recoverable, &DELAYS).await
}

async fn with_delays<F, Fut, T, E>(
    mut attempt: F,
    recoverable: impl Fn(&E) -> bool,
    delays: &[Duration],
) -> Result<T, E>
where
    F: FnMut() -> Fut,
    Fut: Future<Output = Result<T, E>>,
{
    let mut waits = delays.iter();
    loop {
        match attempt().await {
            Ok(value) => return Ok(value),
            Err(error) => {
                let Some(delay) = waits.next().filter(|_| recoverable(&error)) else {
                    return Err(error);
                };
                tokio::time::sleep(*delay).await;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{
        Arc,
        atomic::{AtomicBool, AtomicUsize, Ordering},
    };
    fn runtime() -> tokio::runtime::Runtime {
        tokio::runtime::Builder::new_current_thread()
            .enable_time()
            .build()
            .unwrap()
    }
    #[test]
    fn discovery_can_recover_without_retrying_fatal_errors() {
        runtime().block_on(async {
            let count = AtomicUsize::new(0);
            let result = with_delays(
                || {
                    let attempt = count.fetch_add(1, Ordering::SeqCst);
                    std::future::ready(if attempt < 2 { Err(true) } else { Ok(42) })
                },
                |recoverable| *recoverable,
                &[Duration::ZERO; 3],
            )
            .await;
            assert_eq!(result, Ok(42));
            assert_eq!(count.load(Ordering::SeqCst), 3);
            count.store(0, Ordering::SeqCst);
            let result: Result<(), bool> = with_delays(
                || {
                    count.fetch_add(1, Ordering::SeqCst);
                    std::future::ready(Err(false))
                },
                |recoverable| *recoverable,
                &[Duration::ZERO; 3],
            )
            .await;
            assert_eq!(result, Err(false));
            assert_eq!(count.load(Ordering::SeqCst), 1);
        });
    }
    #[test]
    fn discovery_exhaustion_is_bounded() {
        runtime().block_on(async {
            let count = AtomicUsize::new(0);
            let result: Result<(), bool> = with_delays(
                || {
                    count.fetch_add(1, Ordering::SeqCst);
                    std::future::ready(Err(true))
                },
                |e| *e,
                &[Duration::ZERO; 6],
            )
            .await;
            assert_eq!(result, Err(true));
            assert_eq!(count.load(Ordering::SeqCst), 7);
            assert!(DELAYS.iter().sum::<Duration>() < Duration::from_secs(25));
        });
    }
    #[test]
    fn connection_deadline_drops_a_pending_attempt() {
        struct Guard(Arc<AtomicBool>);
        impl Drop for Guard {
            fn drop(&mut self) {
                self.0.store(true, Ordering::SeqCst);
            }
        }
        runtime().block_on(async {
            let dropped = Arc::new(AtomicBool::new(false));
            let copy = dropped.clone();
            let job = with_delays(
                move || {
                    let guard = Guard(copy.clone());
                    async move {
                        let _guard = guard;
                        std::future::pending::<Result<(), bool>>().await
                    }
                },
                |e| *e,
                &[Duration::ZERO],
            );
            assert!(
                tokio::time::timeout(Duration::from_millis(5), job)
                    .await
                    .is_err()
            );
            assert!(dropped.load(Ordering::SeqCst));
        });
    }
}
