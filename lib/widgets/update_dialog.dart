// 本文件包含的弹窗布局与更新日志富文本样式参考自 FlClash（https://github.com/chen08209/FlClash）项目，
// 原始许可证为 GPL-3.0，来源提交：be84736605527034689c95bf27828ff27d912c5e。
// 对应原文件：lib/common/dialog.dart、lib/providers/actions/common.dart。

import 'package:material_ui/material_ui.dart'
    hide
        AlertDialog,
        ButtonStyle,
        FilledButton,
        IconButton,
        OutlinedButton,
        Switch,
        TextButton;

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'prism.dart';

/// 解析后的 Release 更新日志分节。
class ReleaseNotesSection {
  const ReleaseNotesSection({required this.title, required this.entries});

  final String title;
  final List<String> entries;
}

/// 解析后的 Release 更新日志。
class ParsedReleaseNotes {
  const ParsedReleaseNotes({
    this.summary,
    this.sections = const [],
    this.looseEntries = const [],
  });

  final String? summary;
  final List<ReleaseNotesSection> sections;
  final List<String> looseEntries;

  bool get isEmpty =>
      (summary == null || summary!.isEmpty) &&
      sections.isEmpty &&
      looseEntries.isEmpty;
}

final _h1HeadingPattern = RegExp(r'^#\s+');
final _h2HeadingPattern = RegExp(r'^##\s+(.+)$');
final _bulletPattern = RegExp(r'^[ \t]*[-*][ \t]+(.+)$');
final _ignoredSections = {'贡献者', 'contributors'};
final _breakingSections = {'破坏性变更', 'breaking', 'breaking changes'};

/// 解析 `docs/release/<tag>.md` 风格或通用 Markdown Release 正文。
ParsedReleaseNotes parseReleaseNotes(String? rawBody) {
  if (rawBody == null) {
    return const ParsedReleaseNotes();
  }
  final lines = rawBody.replaceAll('\r\n', '\n').split('\n');
  final summaryBuffer = <String>[];
  final sections = <ReleaseNotesSection>[];
  final looseEntries = <String>[];

  String? currentHeading;
  var currentEntries = <String>[];
  var sawH1 = false;
  var inIgnoredSection = false;

  void flushSection() {
    if (currentHeading != null &&
        !inIgnoredSection &&
        currentEntries.isNotEmpty) {
      sections.add(
        ReleaseNotesSection(
          title: currentHeading,
          entries: List.unmodifiable(currentEntries),
        ),
      );
    }
    currentEntries = <String>[];
  }

  for (final rawLine in lines) {
    final trimmed = rawLine.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    if (!sawH1 &&
        currentHeading == null &&
        _h1HeadingPattern.hasMatch(trimmed)) {
      sawH1 = true;
      continue;
    }
    final h2Match = _h2HeadingPattern.firstMatch(trimmed);
    if (h2Match != null) {
      flushSection();
      currentHeading = h2Match.group(1)!.trim();
      inIgnoredSection = _ignoredSections.contains(
        currentHeading.toLowerCase(),
      );
      continue;
    }
    if (inIgnoredSection) {
      continue;
    }
    final bulletMatch = _bulletPattern.firstMatch(rawLine);
    if (bulletMatch != null) {
      final item = bulletMatch.group(1)!.trim();
      if (item.isNotEmpty) {
        if (currentHeading != null) {
          currentEntries.add(item);
        } else {
          looseEntries.add(item);
        }
      }
      continue;
    }
    if (currentHeading == null) {
      summaryBuffer.add(trimmed);
    } else {
      currentEntries.add(trimmed);
    }
  }
  flushSection();

  return ParsedReleaseNotes(
    summary: summaryBuffer.isEmpty ? null : summaryBuffer.join(' '),
    sections: List.unmodifiable(sections),
    looseEntries: List.unmodifiable(looseEntries),
  );
}

/// 构造更新弹窗正文 `TextSpan`（沿用 FlClash 分节高亮与条目样式）。
TextSpan buildReleaseNotesSpan(
  BuildContext context, {
  required String version,
  String? releaseNotes,
  required String fallbackMessage,
}) {
  final scheme = context.scheme;
  final displayTag = version.startsWith('v') ? version : 'v$version';
  final parsed = parseReleaseNotes(releaseNotes);
  final bodyStyle = AppTextStyle.subheadline.of(context);

  final children = <InlineSpan>[];
  if (parsed.isEmpty) {
    children.add(TextSpan(text: '\n$fallbackMessage', style: bodyStyle));
  } else {
    if (parsed.summary case final summary?) {
      children.add(TextSpan(text: '\n$summary\n', style: bodyStyle));
    }
    if (parsed.sections.isNotEmpty) {
      for (final section in parsed.sections) {
        final isBreaking = _breakingSections.contains(
          section.title.toLowerCase(),
        );
        children.add(
          TextSpan(
            text: '\n${section.title}\n',
            style: AppTextStyle.subheadline
                .of(context, emphasized: true)
                .copyWith(color: isBreaking ? scheme.error : scheme.primary),
          ),
        );
        for (final entry in section.entries) {
          children.add(TextSpan(text: '• $entry\n', style: bodyStyle));
        }
      }
    } else if (parsed.looseEntries.isNotEmpty) {
      children.add(TextSpan(text: '\n', style: bodyStyle));
      for (final entry in parsed.looseEntries) {
        children.add(TextSpan(text: '• $entry\n', style: bodyStyle));
      }
    }
  }

  return TextSpan(
    text: '$displayTag\n',
    style: AppTextStyle.title2.of(context),
    children: children,
  );
}

/// 弹出「发现新版本」对话框。
///
/// 返回 `true` 表示用户选择前往下载，`false` 表示点击次按钮（自动检查时为「不再提醒」，
/// 手动触发时为「取消」），`null` 表示点击空白处或按 Esc 关闭。
Future<bool?> showUpdateAvailableDialog(
  BuildContext context, {
  required String version,
  String? releaseNotes,
  required bool showDoNotRemind,
}) {
  final l10n = AppLocalizations.of(context);
  return showFloatingDialog<bool>(
    context: context,
    child: Builder(
      builder: (dialogContext) => AlertDialog(
        title: l10n.updateDiscoverNewVersion,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              showDoNotRemind ? l10n.updateNoLongerRemind : l10n.commonCancel,
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.updateGoDownload),
          ),
        ],
        child: SelectableText.rich(
          buildReleaseNotesSpan(
            dialogContext,
            version: version,
            releaseNotes: releaseNotes,
            fallbackMessage: l10n.updateAvailableBadge(version),
          ),
          style: const TextStyle(overflow: TextOverflow.visible),
        ),
      ),
    ),
  );
}

/// 弹出「当前应用已经是最新版了」单按钮提示对话框。
Future<void> showUpToDateDialog(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showFloatingDialog<void>(
    context: context,
    child: Builder(
      builder: (dialogContext) => AlertDialog(
        title: l10n.updateCheck,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.commonClose),
          ),
        ],
        child: SelectableText.rich(
          TextSpan(text: l10n.updateUpToDate),
          style: const TextStyle(overflow: TextOverflow.visible),
        ),
      ),
    ),
  );
}
