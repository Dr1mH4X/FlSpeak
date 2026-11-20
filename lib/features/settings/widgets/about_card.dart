import 'dart:async';

import 'package:flutter/material.dart'
    hide
        AlertDialog,
        ButtonStyle,
        Divider,
        FilledButton,
        IconButton,
        OutlinedButton,
        Switch,
        TextButton;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart' show UpdateStateView;

import '../../../core/notices.dart';
import '../../../core/providers.dart';
import '../../../core/update_check.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/prism.dart';
import '../../../widgets/update_dialog.dart';
import '../../../widgets/update_dot.dart';

export '../../../core/update_check.dart' show openExternalUrl;

const String _websiteUrl = 'https://flspeak.dreamhax.cc';
const String _repoUrl = 'https://github.com/Dr1mH4X/FlSpeak';
const String _issuesUrl = 'https://github.com/Dr1mH4X/FlSpeak/issues';
const String _licenseUrl =
    'https://github.com/Dr1mH4X/FlSpeak/blob/main/LICENSE';
const String _tsclientUrl = 'https://github.com/Dr1mH4X/tsclient-rs';
const String _openProtocolUrl =
    'https://github.com/Dr1mH4X/tsclient-rs/blob/master/docs/open-protocol.md';

/// 关于页主信息卡片。
class AboutCard extends ConsumerStatefulWidget {
  const AboutCard({super.key, this.version, this.onOpenUrl});

  final String? version;
  final Future<bool> Function(String url)? onOpenUrl;

  @override
  ConsumerState<AboutCard> createState() => _AboutCardState();
}

class _AboutCardState extends ConsumerState<AboutCard> {
  bool _checkingUpdate = false;

  Future<bool> _openUrl(String url) {
    if (widget.onOpenUrl case final opener?) {
      return opener(url);
    }
    return ref.read(externalUrlOpenerProvider)(url);
  }

  Future<void> _openUpdateDialog(UpdateStateView update) async {
    final version = update.latestVersion;
    if (version == null) return;
    final confirmed = await showUpdateAvailableDialog(
      context,
      version: version,
      releaseNotes: update.releaseNotes,
      showDoNotRemind: false,
    );
    if (!mounted || confirmed != true) return;
    final releaseUrl = update.releaseUrl;
    if (releaseUrl != null) {
      unawaited(_openUrl(releaseUrl));
    }
  }

  Future<void> _checkForUpdates() async {
    if (_checkingUpdate) return;
    setState(() => _checkingUpdate = true);
    final next = await ref.read(updateProvider.notifier).refresh(force: true);
    if (!mounted) return;
    setState(() => _checkingUpdate = false);

    if (next == null) {
      ref
          .read(noticeCenterProvider.notifier)
          .show(
            AppLocalizations.of(context).updateCheckFailed,
            tone: NoticeTone.error,
          );
      return;
    }

    if (next.available && next.latestVersion != null) {
      await _openUpdateDialog(next);
    } else {
      await showUpToDateDialog(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final update = ref.watch(updateProvider);
    final latestVersion = update.latestVersion;
    final String displayVersion =
        widget.version ?? ref.watch(appVersionProvider);

    final sectionBg = surfaceColorFor(SurfaceLevel.block, scheme);

    return SurfaceCard(
      clip: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. 应用图标
            Center(
              child: Image.asset(
                'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png',
                width: 80,
                height: 80,
                filterQuality: FilterQuality.high,
                excludeFromSemantics: true,
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
            const SizedBox(height: 10),

            // 3. 版本号胶囊
            Center(
              child: _VersionPill(
                version: displayVersion,
                hasUpdate: update.available,
                updateLabel: latestVersion == null
                    ? null
                    : l10n.updateAvailableBadge(latestVersion),
              ),
            ),
            const SizedBox(height: 12),

            // 4. 副标题 / 描述
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  l10n.aboutSubtitle,
                  textAlign: TextAlign.center,
                  style: context.texts.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 5. 检查更新按钮
            Center(
              child: TonalButton(
                size: TonalButtonSize.bar,
                glyph: AppGlyphs.sync,
                label: l10n.updateCheck,
                onPressed: _checkingUpdate ? null : _checkForUpdates,
              ),
            ),
            const SizedBox(height: 24),

            // 6. 联系与项目源码
            _InfoSection(
              backgroundColor: sectionBg,
              icon: Icons.mail_outline_rounded,
              title: l10n.aboutSourceAndFeedback,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _BulletLinkRow(
                    label: '${l10n.aboutWebsite}: ',
                    linkText: l10n.aboutWebsiteAction,
                    url: _websiteUrl,
                    onTap: () => _openUrl(_websiteUrl),
                  ),
                  const SizedBox(height: 8),
                  _BulletLinkRow(
                    label: '${l10n.aboutSourceCode}: ',
                    linkText: 'GitHub',
                    url: _repoUrl,
                    onTap: () => _openUrl(_repoUrl),
                  ),
                  const SizedBox(height: 8),
                  _BulletLinkRow(
                    label: '${l10n.aboutIssueTracker}: ',
                    linkText: 'GitHub Issue',
                    url: _issuesUrl,
                    onTap: () => _openUrl(_issuesUrl),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // 7. 许可证卡片
            _InfoSection(
              backgroundColor: sectionBg,
              icon: Icons.description_outlined,
              title: l10n.aboutLicense,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Semantics(
                  link: true,
                  label: 'GNU Affero General Public License v3.0 (AGPL-3.0)',
                  child: AnimatedInkWell(
                    customBorder: AppShape.sm,
                    onTap: () => _openUrl(_licenseUrl),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 4,
                        horizontal: 2,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              'GNU Affero General Public License v3.0 (AGPL-3.0)',
                              style: context.texts.bodyMedium?.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.underline,
                                decorationColor: scheme.primary.withValues(
                                  alpha: 0.4,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.open_in_new_rounded,
                            size: 14,
                            color: scheme.primary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 6. 分割线与底部 Powered by tsclient-rs · Supports OpenProtocol
            const Divider(height: 1),
            const SizedBox(height: 16),
            Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 4,
                children: [
                  Text(
                    'Powered by ',
                    style: context.texts.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                  ),
                  _InteractiveLink(
                    text: 'tsclient-rs',
                    url: _tsclientUrl,
                    onTap: () => _openUrl(_tsclientUrl),
                    textStyle: context.texts.bodySmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    ' · Supports ',
                    style: context.texts.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                  ),
                  _InteractiveLink(
                    text: 'OpenProtocol',
                    url: _openProtocolUrl,
                    onTap: () => _openUrl(_openProtocolUrl),
                    textStyle: context.texts.bodySmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
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
      decoration: ShapeDecoration(color: backgroundColor, shape: AppShape.md),
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
      crossAxisAlignment: CrossAxisAlignment.center,
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
        _InteractiveLink(text: linkText, url: url, onTap: onTap),
      ],
    );
  }
}

class _InteractiveLink extends StatefulWidget {
  const _InteractiveLink({
    required this.text,
    required this.url,
    required this.onTap,
    this.textStyle,
  });

  final String text;
  final String url;
  final VoidCallback onTap;
  final TextStyle? textStyle;

  @override
  State<_InteractiveLink> createState() => _InteractiveLinkState();
}

class _InteractiveLinkState extends State<_InteractiveLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final baseStyle =
        widget.textStyle ??
        context.texts.bodyMedium?.copyWith(
          color: scheme.primary,
          fontWeight: FontWeight.w600,
        );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Semantics(
        link: true,
        label: widget.text,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: ShapeDecoration(
              color: _hovered
                  ? scheme.primary.withValues(alpha: 0.1)
                  : Colors.transparent,
              shape: AppShape.xs,
            ),
            child: Text(
              widget.text,
              style: baseStyle?.copyWith(
                color: _hovered
                    ? scheme.primary
                    : scheme.primary.withValues(alpha: 0.9),
                decoration: TextDecoration.underline,
                decorationColor: _hovered
                    ? scheme.primary
                    : scheme.primary.withValues(alpha: 0.4),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VersionPill extends StatelessWidget {
  const _VersionPill({
    required this.version,
    required this.hasUpdate,
    this.updateLabel,
  });

  final String version;
  final bool hasUpdate;
  final String? updateLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final label = version.startsWith('v') ? version : 'v$version';

    final pill = DecoratedBox(
      decoration: ShapeDecoration(color: scheme.primary, shape: AppShape.full),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Text(
          label,
          style: context.texts.labelSmall?.copyWith(
            color: scheme.onPrimary,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        pill,
        if (hasUpdate)
          Positioned(
            top: -2,
            right: -2,
            child: UpdateDot(
              semanticLabel: updateLabel,
              size: 10,
              borderColor: context.cardColor,
            ),
          ),
      ],
    );
  }
}
