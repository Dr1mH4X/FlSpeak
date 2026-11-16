//! FFI 边界。`api/` 是 flutter_rust_bridge 唯一解析的模块，其余模块不进入桥。

pub mod api;
mod frb_generated;

#[cfg(target_os = "android")]
mod android_context {
    use std::sync::Mutex;

    use jni::EnvUnowned;
    use jni::objects::JObject;

    static INITIALIZED: Mutex<bool> = Mutex::new(false);

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_com_dr1mh4x_flspeak_MainActivity_nativeInitAndroidContext<
        'caller,
    >(
        mut unowned_env: EnvUnowned<'caller>,
        _this: JObject<'caller>,
        context: JObject<'caller>,
    ) {
        unowned_env
            .with_env(|env| -> jni::errors::Result<()> {
                let mut initialized = INITIALIZED
                    .lock()
                    .unwrap_or_else(|poisoned| poisoned.into_inner());
                if *initialized {
                    return Ok(());
                }
                if context.is_null() {
                    return Err(jni::errors::Error::NullPtr("context"));
                }
                let vm = env.get_java_vm()?;
                let app_context = env.new_global_ref(&context)?;
                if app_context.is_null() {
                    return Err(jni::errors::Error::NullPtr("app_context"));
                }
                // SAFETY: GlobalRef 与 JavaVM 指针在进程生命周期内持续有效，且仅初始化一次。
                unsafe {
                    ndk_context::initialize_android_context(
                        vm.get_raw().cast(),
                        app_context.into_raw().cast(),
                    );
                }
                *initialized = true;
                Ok(())
            })
            .resolve::<jni::errors::ThrowRuntimeExAndDefault>();
    }
}
