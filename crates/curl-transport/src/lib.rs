use std::time::Duration;

use godot::{classes::Engine, prelude::*};
use tokio::{
    runtime::{self, Runtime},
    task::JoinHandle,
};

const ALPN: &[u8] = b"pebble-granite/iroh/1";

mod client;
mod connection;
mod identity;
mod retry;
mod server;

// Android's DNS resolver needs an application context. Keep a global JNI ref
// for the process lifetime; never retain an Activity or call Godot off-thread.
#[cfg(target_os = "android")]
static ANDROID_CONTEXT: std::sync::OnceLock<jni::objects::GlobalRef> = std::sync::OnceLock::new();

#[cfg(target_os = "android")]
#[unsafe(no_mangle)]
pub extern "system" fn Java_dev_pebblegranite_platform_PebbleMobile_initializeIrohNative(
    env: jni::JNIEnv,
    _class: jni::objects::JClass,
    context: jni::objects::JObject,
) -> jni::sys::jboolean {
    if ANDROID_CONTEXT.get().is_some() {
        return jni::sys::JNI_TRUE;
    }
    let Ok(vm) = env.get_java_vm() else {
        return jni::sys::JNI_FALSE;
    };
    let Ok(global) = env.new_global_ref(context) else {
        return jni::sys::JNI_FALSE;
    };
    let global = ANDROID_CONTEXT.get_or_init(|| global);
    // SAFETY: JavaVM lives for this process; OnceLock retains a GlobalRef.
    unsafe {
        iroh::dns::install_android_jni_context(
            vm.get_java_vm_pointer().cast(),
            global.as_obj().as_raw().cast(),
        );
    }
    jni::sys::JNI_TRUE
}

struct MyExtension;

#[gdextension]
unsafe impl ExtensionLibrary for MyExtension {
    fn on_stage_init(stage: InitStage) {
        if stage == InitStage::Scene {
            Engine::singleton().register_singleton("IrohRuntime", &IrohRuntime::new_alloc());
        }
    }

    fn on_stage_deinit(stage: InitStage) {
        if stage == InitStage::Scene {
            let mut engine = Engine::singleton();
            let singleton = engine
                .get_singleton("IrohRuntime")
                .expect("singleton not found");
            engine.unregister_singleton("IrohRuntime");
            singleton.free();
        }
    }
}

#[derive(GodotClass)]
#[class(tool, base=Object)]
pub struct IrohRuntime {
    base: Base<Object>,
    runtime: Option<Runtime>,
}

#[godot_api]
impl IObject for IrohRuntime {
    fn init(base: Base<Object>) -> Self {
        Self {
            base,
            runtime: None,
        }
    }
}

impl IrohRuntime {
    fn ensure_runtime(&mut self) -> &Runtime {
        self.runtime.get_or_insert_with(|| {
            runtime::Builder::new_multi_thread()
                .worker_threads(2)
                .enable_all()
                .build()
                .expect("Iroh runtime initialization failed")
        })
    }
}

#[godot_api]
impl IrohRuntime {
    pub fn spawn<F>(future: F) -> JoinHandle<F::Output>
    where
        F: Future + Send + 'static,
        F::Output: Send + 'static,
    {
        Engine::singleton()
            .get_singleton("IrohRuntime")
            .expect("singleton not found")
            .cast::<Self>()
            .bind_mut()
            .ensure_runtime()
            .spawn(future)
    }

    pub fn block_on<F: Future>(future: F) -> F::Output {
        Engine::singleton()
            .get_singleton("IrohRuntime")
            .expect("singleton not found")
            .cast::<Self>()
            .bind_mut()
            .ensure_runtime()
            .block_on(future)
    }
}

impl Drop for IrohRuntime {
    fn drop(&mut self) {
        if let Some(runtime) = std::mem::take(&mut self.runtime) {
            runtime.shutdown_timeout(Duration::from_secs(5));
        }
    }
}
