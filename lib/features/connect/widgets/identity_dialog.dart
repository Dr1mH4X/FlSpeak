import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/common.dart';
import '../../../widgets/monogram.dart';

/// 管理身份。后端只有单一身份，所以这一步的实际内容就是改昵称：
/// 点铅笔就地编辑，回车或勾保存，避免再套一层「编辑」对话框。
Future<void> showIdentityDialog(
  BuildContext context, {
  required String nickname,
  required ValueChanged<String> onRename,
}) {
  return showAppModal<void>(
    context,
    title: AppLocalizations.of(context).identityTitle,
    builder: (context) =>
        _IdentityDialogContent(nickname: nickname, onRename: onRename),
    footer: (context) => FilledButton(
      onPressed: () => Navigator.of(context).pop(),
      child: Text(AppLocalizations.of(context).commonDone),
    ),
  );
}

class _IdentityDialogContent extends StatefulWidget {
  const _IdentityDialogContent({
    required this.nickname,
    required this.onRename,
  });

  final String nickname;
  final ValueChanged<String> onRename;

  @override
  State<_IdentityDialogContent> createState() => _IdentityDialogContentState();
}

class _IdentityDialogContentState extends State<_IdentityDialogContent> {
  late final TextEditingController _draft = TextEditingController();
  late String _nickname = widget.nickname;
  bool _editing = false;
  String? _error;

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  void _startEditing() {
    setState(() {
      _editing = true;
      _error = null;
      _draft.text = _nickname;
      _draft.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _draft.text.length,
      );
    });
  }

  void _cancelEditing() {
    setState(() {
      _editing = false;
      _error = null;
    });
  }

  void _commit() {
    final value = _draft.text.trim();
    if (value.isEmpty) {
      setState(
        () => _error = AppLocalizations.of(context).identityNicknameEmpty,
      );
      return;
    }
    widget.onRename(value);
    setState(() {
      _nickname = value;
      _editing = false;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        // 不透明 container 对：透明度叠底在暗色下发闷，正文对比也随底色漂。
        color: scheme.secondaryContainer,
        borderRadius: Radii.xxlAll,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: AnimatedSwitcher(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : Motion.effectsFast,
        switchInCurve: Motion.effectsFastCurve,
        switchOutCurve: Motion.effectsFastCurve.flipped,
        child: _editing
            ? KeyedSubtree(
                key: const ValueKey('identity-editor'),
                child: _buildEditor(context, l10n),
              )
            : KeyedSubtree(
                key: const ValueKey('identity-row'),
                child: _buildRow(context, l10n),
              ),
      ),
    );
  }

  Widget _buildRow(BuildContext context, AppLocalizations l10n) {
    final scheme = context.scheme;
    return Row(
      children: [
        IdentityAvatar(nickname: _nickname, size: 36),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _nickname,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.texts.bodyLarge?.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                l10n.serversUsedBy(1),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.texts.bodySmall?.copyWith(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: scheme.primary,
            shape: BoxShape.circle,
            border: Border.all(color: scheme.primary),
          ),
          child: Icon(Icons.check_rounded, size: 12, color: scheme.onPrimary),
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: l10n.identityRename,
          onPressed: _startEditing,
          iconSize: 16,
          color: scheme.onSurfaceVariant,
          style: IconButton.styleFrom(
            minimumSize: const Size(Sizes.touch, Sizes.touch),
            maximumSize: const Size(Sizes.touch, Sizes.touch),
            padding: EdgeInsets.zero,
          ),
          icon: const Icon(Icons.edit_rounded),
        ),
      ],
    );
  }

  Widget _buildEditor(BuildContext context, AppLocalizations l10n) {
    final scheme = context.scheme;
    return Row(
      children: [
        IdentityAvatar(
          nickname: _draft.text.trim().isEmpty ? _nickname : _draft.text.trim(),
          size: 36,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _draft,
            autofocus: true,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            inputFormatters: [LengthLimitingTextInputFormatter(32)],
            style: context.texts.bodyLarge?.copyWith(fontSize: 14),
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _commit(),
            decoration: InputDecoration(
              isDense: true,
              hintText: l10n.connectNicknameLabel,
              errorText: _error,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 8,
              ),
              border: OutlineInputBorder(borderRadius: Radii.smallAll),
            ),
          ),
        ),
        IconButton(
          tooltip: l10n.identitySave,
          onPressed: _commit,
          iconSize: 16,
          color: scheme.primary,
          style: IconButton.styleFrom(
            minimumSize: const Size(Sizes.touch, Sizes.touch),
            maximumSize: const Size(Sizes.touch, Sizes.touch),
            padding: EdgeInsets.zero,
          ),
          icon: const Icon(Icons.check_rounded),
        ),
        IconButton(
          tooltip: l10n.identityCancel,
          onPressed: _cancelEditing,
          iconSize: 16,
          color: scheme.onSurfaceVariant,
          style: IconButton.styleFrom(
            minimumSize: const Size(Sizes.touch, Sizes.touch),
            maximumSize: const Size(Sizes.touch, Sizes.touch),
            padding: EdgeInsets.zero,
          ),
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    );
  }
}
