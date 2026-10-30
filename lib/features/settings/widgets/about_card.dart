import 'dart:io' show Platform, Process;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';

const String _repoUrl = 'https://github.com/Dr1mH4X/FlSpeak';
const String _issuesUrl = 'https://github.com/Dr1mH4X/FlSpeak/issues';
const String _licenseUrl =
    'https://github.com/Dr1mH4X/FlSpeak/blob/main/LICENSE';

/// 跨平台在系统默认浏览器中打开外部链接。
Future<bool> openExternalUrl(String url) async {
  if (kIsWeb) return false;
  try {
    if (Platform.isMacOS) {
      final res = await Process.run('open', [url]);
      return res.exitCode == 0;
    } else if (Platform.isWindows) {
      final res = await Process.run('cmd', ['/c', 'start', '', url]);
      return res.exitCode == 0;
    } else if (Platform.isLinux) {
      final res = await Process.run('xdg-open', [url]);
      return res.exitCode == 0;
    }
  } catch (_) {
    // 忽略异常，由调用方或界面降级处理
  }
  return false;
}

/// 关于页主信息卡片。
class AboutCard extends StatelessWidget {
  const AboutCard({super.key, this.onOpenUrl = openExternalUrl});

  final Future<bool> Function(String url) onOpenUrl;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final isDark = context.isDark;

    final cardBg = isDark
        ? scheme.surfaceContainerLow
        : scheme.surfaceContainerLowest;
    final sectionBg = isDark
        ? scheme.surfaceContainer
        : scheme.surfaceContainerLow;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: Radii.xxlAll,
            border: Border.all(color: hairlineSide(context).color),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. 图标占位
              Center(
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: isDark
                        ? scheme.surfaceContainerHigh
                        : scheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.6),
                      width: 1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // 2. 应用名称
              Center(
                child: Text(
                  l10n.appName,
                  style: context.texts.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 24,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              const SizedBox(height: 6),

              // 3. 副标题 / 描述
              Center(
                child: Text(
                  l10n.aboutSubtitle,
                  style: context.texts.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // 4. 联系与项目源码
              _InfoSection(
                backgroundColor: sectionBg,
                icon: Icons.mail_outline_rounded,
                title: l10n.aboutSourceAndFeedback,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _BulletLinkRow(
                      label: '${l10n.aboutSourceCode}: ',
                      linkText: 'GitHub',
                      url: _repoUrl,
                      onTap: () => onOpenUrl(_repoUrl),
                    ),
                    const SizedBox(height: 6),
                    _BulletLinkRow(
                      label: '${l10n.aboutIssueTracker}: ',
                      linkText: 'GitHub Issue',
                      url: _issuesUrl,
                      onTap: () => onOpenUrl(_issuesUrl),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 5. 许可证卡片
              _InfoSection(
                backgroundColor: sectionBg,
                icon: Icons.description_outlined,
                title: l10n.aboutLicense,
                child: Semantics(
                  link: true,
                  label: 'GNU Affero General Public License v3.0 (AGPL-3.0)',
                  child: InkWell(
                    borderRadius: Radii.smallAll,
                    onTap: () => onOpenUrl(_licenseUrl),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        'GNU Affero General Public License v3.0 (AGPL-3.0)',
                        style: context.texts.bodyMedium?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // 6. 分割线与底部 Powered by
              Divider(
                color: scheme.outlineVariant.withValues(alpha: 0.5),
                height: 1,
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  'Powered by Flutter & Rust',
                  style: context.texts.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  const _InfoSection({
    required this.backgroundColor,
    required this.icon,
    required this.title,
    required this.child,
  });

  final Color backgroundColor;
  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;

    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: IconSizes.medium,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: context.texts.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _BulletLinkRow extends StatelessWidget {
  const _BulletLinkRow({
    required this.label,
    required this.linkText,
    required this.url,
    required this.onTap,
  });

  final String label;
  final String linkText;
  final String url;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '•  ',
          style: context.texts.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        Text(
          label,
          style: context.texts.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        Semantics(
          link: true,
          label: '$label$linkText',
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                linkText,
                style: context.texts.bodyMedium?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                  decorationColor: scheme.primary.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
