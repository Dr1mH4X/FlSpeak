import type {
  ArchId,
  AssetFormatBadge,
  ClassifiedAsset,
  DetectedOs,
  DeviceInfo,
  PlatformId,
  RawReleaseAsset,
} from '../types/release';

export function formatBytesToMb(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes <= 0) return '0.0 MB';
  const mb = bytes / (1024 * 1024);
  if (mb < 0.1) {
    const kb = bytes / 1024;
    return `${kb.toFixed(1)} KB`;
  }
  return `${mb.toFixed(1)} MB`;
}

export function detectMacGpuArchitecture(): {
  arch: ArchId;
  isAppleSilicon: boolean;
} | null {
  if (typeof document === 'undefined') return null;
  try {
    const canvas = document.createElement('canvas');
    const gl =
      (canvas.getContext('webgl') as WebGLRenderingContext | null) ||
      (canvas.getContext('experimental-webgl') as WebGLRenderingContext | null);
    if (!gl) return null;
    const debugInfo = gl.getExtension('WEBGL_debug_renderer_info');
    const renderer = debugInfo
      ? String(gl.getParameter(debugInfo.UNMASKED_RENDERER_WEBGL) || '')
      : String(gl.getParameter(gl.RENDERER) || '');

    if (/apple\s+m\d|apple\s+gpu/i.test(renderer)) {
      return { arch: 'arm64', isAppleSilicon: true };
    }
    if (/intel|amd|radeon|nvidia/i.test(renderer)) {
      return { arch: 'x64', isAppleSilicon: false };
    }
  } catch {
    // WebGL blocked or unavailable
  }
  return null;
}

export function parseOsFromUserAgent(
  ua: string,
  platformStr = '',
  maxTouchPoints = 0
): DetectedOs {
  const lowerUa = ua.toLowerCase();
  const lowerPlat = platformStr.toLowerCase();

  if (
    /iphone|ipad|ipod/.test(lowerUa) ||
    (lowerPlat.includes('mac') && maxTouchPoints > 1)
  ) {
    return 'ios';
  }
  if (/android/.test(lowerUa)) {
    return 'android';
  }
  if (/win/.test(lowerPlat) || /windows/.test(lowerUa)) {
    return 'windows';
  }
  if (/mac/.test(lowerPlat) || /macintosh|mac os x/.test(lowerUa)) {
    return 'macos';
  }
  if (/linux|x11|wayland/.test(lowerPlat) || /linux/.test(lowerUa)) {
    return 'linux';
  }
  return 'unknown';
}

export function parseArchFromStrings(ua: string, archHint = ''): ArchId | null {
  const combined = `${ua} ${archHint}`.toLowerCase();
  if (/\b(arm64|aarch64|armv8|apple)\b/.test(combined)) {
    return 'arm64';
  }
  if (/\b(x86_64|x64|amd64|wow64|win64|intel)\b/.test(combined)) {
    return 'x64';
  }
  return null;
}

export async function detectDevice(): Promise<DeviceInfo> {
  if (typeof navigator === 'undefined') {
    return {
      os: 'windows',
      platform: 'windows',
      arch: 'x64',
      isAppleSilicon: false,
    };
  }

  const ua = navigator.userAgent || '';
  const plat = navigator.platform || '';
  const maxTouch = navigator.maxTouchPoints || 0;
  const os = parseOsFromUserAgent(ua, plat, maxTouch);

  const targetPlatform: PlatformId =
    os === 'windows' || os === 'macos' || os === 'linux' || os === 'android'
      ? os
      : 'windows';

  let arch: ArchId = os === 'android' || os === 'macos' ? 'arm64' : 'x64';
  let isAppleSilicon = os === 'macos';

  try {
    const uaData = (
      navigator as Navigator & {
        userAgentData?: {
          getHighEntropyValues?: (
            hints: string[]
          ) => Promise<{ architecture?: string; bitness?: string }>;
        };
      }
    ).userAgentData;

    if (uaData?.getHighEntropyValues) {
      const highEntropy = await uaData.getHighEntropyValues([
        'architecture',
        'bitness',
      ]);
      const hinted = parseArchFromStrings(ua, highEntropy?.architecture || '');
      if (hinted) {
        arch = hinted;
        if (os === 'macos') {
          isAppleSilicon = arch === 'arm64';
        }
      }
    } else {
      const fromUa = parseArchFromStrings(ua);
      if (fromUa) arch = fromUa;
    }
  } catch {
    // Fallback
  }

  if (os === 'macos') {
    const gpuInfo = detectMacGpuArchitecture();
    if (gpuInfo) {
      arch = gpuInfo.arch;
      isAppleSilicon = gpuInfo.isAppleSilicon;
    }
  }

  return {
    os,
    platform: targetPlatform,
    arch,
    isAppleSilicon,
  };
}

export function classifyReleaseAsset(
  raw: RawReleaseAsset
): ClassifiedAsset | null {
  const name = (raw.name || '').trim();
  if (!name || /sha256sums/i.test(name)) return null;
  const lower = name.toLowerCase();
  const sizeFormatted = formatBytesToMb(raw.size);
  const sha256 = raw.sha256 || null;

  // Android APK
  if (lower.endsWith('.apk')) {
    let androidAbi: ClassifiedAsset['androidAbi'] = 'universal';
    let arch: ArchId = 'arm64';
    let kindKey: ClassifiedAsset['kindKey'] = 'apkUniversal';
    let recommended = true;

    if (/arm64-v8a|arm64|aarch64/.test(lower)) {
      androidAbi = 'arm64-v8a';
      arch = 'arm64';
      kindKey = 'apkArm64';
      recommended = true;
    } else if (/armeabi-v7a|armv7/.test(lower)) {
      androidAbi = 'armeabi-v7a';
      arch = 'arm64';
      kindKey = 'apkArmv7';
      recommended = false;
    } else if (/x86_64|amd64|x64/.test(lower)) {
      androidAbi = 'x86_64';
      arch = 'x64';
      kindKey = 'apkX64';
      recommended = false;
    }

    return {
      name,
      size: raw.size,
      sizeFormatted,
      downloadUrl: raw.browser_download_url,
      sha256,
      platform: 'android',
      arch,
      androidAbi,
      badge: 'APK',
      kindKey,
      recommended,
    };
  }

  const isArm64 = /arm64|aarch64|apple/.test(lower);
  const arch: ArchId = isArm64 ? 'arm64' : 'x64';

  // macOS (.dmg, .app.tar.gz, or macos/darwin in filename)
  if (
    lower.endsWith('.dmg') ||
    lower.endsWith('.app.tar.gz') ||
    ((lower.includes('macos') || lower.includes('darwin')) &&
      (lower.endsWith('.zip') || lower.endsWith('.tar.gz')))
  ) {
    const isDmg = lower.endsWith('.dmg');
    const badge: AssetFormatBadge = isDmg
      ? 'DMG'
      : lower.endsWith('.zip')
        ? 'ZIP'
        : 'TAR.GZ';
    const hasExplicitX64 = /x64|amd64|x86_64|intel/.test(lower);
    const macChip: ClassifiedAsset['macChip'] = isArm64
      ? 'apple-silicon'
      : hasExplicitX64
        ? 'intel'
        : 'universal';
    const macArch: ArchId = macChip === 'intel' ? 'x64' : 'arm64';

    return {
      name,
      size: raw.size,
      sizeFormatted,
      downloadUrl: raw.browser_download_url,
      sha256,
      platform: 'macos',
      arch: macArch,
      macChip,
      badge,
      kindKey: isDmg ? 'dmg' : 'appArchive',
      recommended: isDmg || !lower.endsWith('.tar.gz'),
    };
  }

  // Linux (.deb, .rpm, .AppImage, or linux in filename)
  if (
    lower.endsWith('.deb') ||
    lower.endsWith('.rpm') ||
    lower.endsWith('.appimage') ||
    (lower.includes('linux') &&
      (lower.endsWith('.tar.gz') ||
        lower.endsWith('.tgz') ||
        lower.endsWith('.zip')))
  ) {
    let badge: AssetFormatBadge = 'TAR.GZ';
    let kindKey: ClassifiedAsset['kindKey'] = 'tarball';
    let recommended = false;

    if (lower.endsWith('.deb')) {
      badge = 'DEB';
      kindKey = 'deb';
      recommended = true;
    } else if (lower.endsWith('.rpm')) {
      badge = 'RPM';
      kindKey = 'rpm';
    } else if (lower.endsWith('.appimage')) {
      badge = 'APPIMAGE';
      kindKey = 'appimage';
    } else {
      badge = 'TAR.GZ';
      kindKey = 'tarball';
      recommended = true;
    }

    return {
      name,
      size: raw.size,
      sizeFormatted,
      downloadUrl: raw.browser_download_url,
      sha256,
      platform: 'linux',
      arch,
      badge,
      kindKey,
      recommended,
    };
  }

  // Windows (.exe, .msi, or windows/win in filename with .zip/.7z)
  if (
    lower.endsWith('.exe') ||
    lower.endsWith('.msi') ||
    ((lower.includes('windows') || lower.includes('win')) &&
      (lower.endsWith('.zip') || lower.endsWith('.7z')))
  ) {
    const isInstaller = lower.endsWith('.exe') || lower.endsWith('.msi');
    const badge: AssetFormatBadge = lower.endsWith('.msi')
      ? 'MSI'
      : lower.endsWith('.exe')
        ? 'EXE'
        : lower.endsWith('.7z')
          ? '7Z'
          : 'ZIP';

    return {
      name,
      size: raw.size,
      sizeFormatted,
      downloadUrl: raw.browser_download_url,
      sha256,
      platform: 'windows',
      arch,
      badge,
      kindKey: isInstaller ? 'installer' : 'portable',
      recommended: isInstaller,
    };
  }

  return null;
}

export function classifyAllAssets(
  rawAssets: RawReleaseAsset[]
): ClassifiedAsset[] {
  if (!Array.isArray(rawAssets)) return [];
  const list: ClassifiedAsset[] = [];
  for (const raw of rawAssets) {
    const item = classifyReleaseAsset(raw);
    if (item) list.push(item);
  }

  const groups = new Map<string, ClassifiedAsset[]>();
  for (const item of list) {
    const key =
      item.platform === 'android' || item.platform === 'macos'
        ? item.platform
        : `${item.platform}:${item.arch}`;
    const arr = groups.get(key) || [];
    arr.push(item);
    groups.set(key, arr);
  }

  for (const arr of groups.values()) {
    if (!arr.some((a) => a.recommended) && arr.length > 0) {
      arr[0].recommended = true;
    }
  }

  return list;
}

export function findRecommendedAsset(
  assets: ClassifiedAsset[],
  platform: PlatformId,
  arch: ArchId
): ClassifiedAsset | null {
  const platformAssets = assets.filter((a) => a.platform === platform);
  if (platformAssets.length === 0) return null;

  const archMatches = platformAssets.filter((a) => a.arch === arch);
  const pool = archMatches.length > 0 ? archMatches : platformAssets;

  return pool.find((a) => a.recommended) || pool[0] || null;
}
