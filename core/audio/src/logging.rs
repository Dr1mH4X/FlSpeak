#[macro_export]
macro_rules! log_error {
    ($($field:ident = $val:expr),* $(,)?; $msg:literal) => {
        tracing::error!(target: module_path!(), $($field = $val,)* $msg)
    };
    ($msg:literal) => {
        tracing::error!(target: module_path!(), $msg)
    };
}

#[macro_export]
macro_rules! log_warn {
    ($($field:ident = $val:expr),* $(,)?; $msg:literal) => {
        tracing::warn!(target: module_path!(), $($field = $val,)* $msg)
    };
    ($msg:literal) => {
        tracing::warn!(target: module_path!(), $msg)
    };
}

#[macro_export]
macro_rules! log_info {
    ($($field:ident = $val:expr),* $(,)?; $msg:literal) => {
        tracing::info!(target: module_path!(), $($field = $val,)* $msg)
    };
    ($msg:literal) => {
        tracing::info!(target: module_path!(), $msg)
    };
}

#[macro_export]
macro_rules! log_debug {
    ($($field:ident = $val:expr),* $(,)?; $msg:literal) => {
        tracing::debug!(target: module_path!(), $($field = $val,)* $msg)
    };
    ($msg:literal) => {
        tracing::debug!(target: module_path!(), $msg)
    };
}

#[cfg(test)]
mod tests {
    #[test]
    fn test_logging_macros_compile() {
        log_error!("test error message");
        log_warn!("test warn message");
        log_info!("test info message");
        log_debug!("test debug message");

        let foo = 42;
        let bar = "val";
        log_error!(foo = foo, bar = bar; "test error with fields");
        log_warn!(foo = foo, bar = bar; "test warn with fields");
        log_info!(foo = foo; "test info with field");
        log_debug!(bar = bar; "test debug with field");
    }
}
