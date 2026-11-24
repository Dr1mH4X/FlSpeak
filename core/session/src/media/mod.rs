//! 本地媒体磁盘缓存与第三方图片传输模块。

mod avatars;
mod cache;
mod icons;
mod image_upload;
mod images;
mod self_avatar;

pub use avatars::MAX_AVATAR_BYTES;
pub use image_upload::{upload_image, validate_image_host};
pub use images::{ImageError, MAX_IMAGE_BYTES, fetch_image};

pub(crate) use avatars::{
    AvatarDiskQueue, is_supported_image as is_supported_avatar_image,
    validate_size as validate_avatar_size,
};
pub(crate) use icons::IconCache;

#[cfg(test)]
pub(crate) use avatars::{load_hit as load_avatar_hit, save as save_avatar};
#[cfg(test)]
pub(crate) use self_avatar::{
    load as load_self_avatar_snapshot, save as save_self_avatar_snapshot,
};
