export type PlatformId = 'windows' | 'macos' | 'linux' | 'android';

export type DetectedOs = PlatformId | 'ios' | 'unknown';

export type ArchId = 'x64' | 'arm64';

export type AssetFormatBadge =
  | 'EXE'
  | 'MSI'
  | 'ZIP'
  | '7Z'
  | 'DMG'
  | 'TAR.GZ'
  | 'DEB'
  | 'RPM'
  | 'APPIMAGE'
  | 'APK';

export interface RawReleaseAsset {
  name: string;
  size: number;
  browser_download_url: string;
  content_type?: string;
  sha256?: string | null;
}

export interface ClassifiedAsset {
  name: string;
  size: number;
  sizeFormatted: string;
  downloadUrl: string;
  sha256: string | null;
  platform: PlatformId;
  arch: ArchId;
  androidAbi?: 'arm64-v8a' | 'armeabi-v7a' | 'x86_64' | 'universal';
  macChip?: 'apple-silicon' | 'intel' | 'universal';
  badge: AssetFormatBadge;
  kindKey:
    | 'installer'
    | 'portable'
    | 'dmg'
    | 'appArchive'
    | 'deb'
    | 'rpm'
    | 'appimage'
    | 'tarball'
    | 'apkArm64'
    | 'apkArmv7'
    | 'apkX64'
    | 'apkUniversal';
  recommended: boolean;
}

export interface ReleaseManifest {
  repo: string;
  tag: string | null;
  name: string | null;
  publishedAt: string | null;
  htmlUrl: string;
  stars: number | null;
  sha256SumsUrl: string | null;
  assets: RawReleaseAsset[];
}

export type ChangelogCategory =
  | 'breaking'
  | 'feat'
  | 'fix'
  | 'perf'
  | 'revert';

export interface ChangelogItem {
  id: string;
  category: ChangelogCategory;
  scope: string | null;
  description: string;
  shortHash: string | null;
  commitUrl: string | null;
}

export interface ChangelogSection {
  category: ChangelogCategory;
  items: ChangelogItem[];
}

export interface ChangelogVersion {
  version: string;
  anchorId: string;
  date: string;
  year: string;
  compareUrl: string | null;
  isTagRelease: boolean;
  sections: ChangelogSection[];
}

export interface DeviceInfo {
  os: DetectedOs;
  platform: PlatformId;
  arch: ArchId;
  isAppleSilicon: boolean;
}
