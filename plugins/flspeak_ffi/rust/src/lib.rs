//! FFI 边界。`api/` 是 flutter_rust_bridge 唯一解析的模块，其余模块不进入桥。

pub mod api;
mod frb_generated;
