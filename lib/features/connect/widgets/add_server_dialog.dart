import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';

import '../../../core/models.dart';
import '../../../core/server_icon.dart';
import '../../../widgets/server_icon_picker.dart';
import '../../../widgets/expressive_frame.dart';
import '../../../core/providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/common.dart';

/// 添加服务器：只收 IP/域名与备注名；官方基础设施的最终边界由 Rust 决定。
///
/// 校验失败时错误写在地址字段下方，不弹第二个对话框——用户正在这一行输入。
Future<ServerProfileView?> showAddServerDialog(BuildContext context) {
  final formKey = GlobalKey<_AddServerFormState>();
  final submitting = ValueNotifier<bool>(false);

  return showAppModal<ServerProfileView>(
    context,
    title: AppLocalizations.of(context).serverAdd,
    builder: (context) => _AddServerForm(key: formKey, submitting: submitting),
    footer: (context) => ValueListenableBuilder<bool>(
      valueListenable: submitting,
      builder: (context, busy, _) {
        final l10n = AppLocalizations.of(context);
        final scheme = context.scheme;
        // 底部操作栏可用宽度随窗口变化，Wrap 在极端字号下换行而不是撑破。
        return Flexible(
          child: Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton(
                onPressed: busy ? null : () => Navigator.of(context).pop(),
                child: Text(l10n.commonCancel),
              ),
              FilledButton(
                onPressed: busy ? null : () => formKey.currentState?.submit(),
                child: AnimatedSwitcher(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : Motion.effectsFast,
                  switchInCurve: Motion.effectsFastCurve,
                  switchOutCurve: Motion.effectsFastCurve.flipped,
                  child: busy
                      ? Row(
                          key: const ValueKey('busy'),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: scheme.onPrimary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(l10n.serverAddAndConnecting),
                          ],
                        )
                      : Row(
                          key: const ValueKey('idle'),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(l10n.serverAddAndConnect),
                            const SizedBox(width: 8),
                            const Icon(Icons.arrow_forward_rounded, size: 16),
                          ],
                        ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

class _AddServerForm extends ConsumerStatefulWidget {
  const _AddServerForm({required this.submitting, super.key});

  final ValueNotifier<bool> submitting;

  @override
  ConsumerState<_AddServerForm> createState() => _AddServerFormState();
}

class _AddServerFormState extends ConsumerState<_AddServerForm> {
  ServerIcon _icon = ServerIcon.community;
  final _address = TextEditingController();
  final _label = TextEditingController();
  final _addressFocus = FocusNode();

  String? _error;
  bool _submitting = false;

  @override
  void dispose() {
    _address.dispose();
    _label.dispose();
    _addressFocus.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (_submitting) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    final address = _address.text.trim();
    if (address.isEmpty) {
      setState(() => _error = l10n.serverAddressRequired);
      _addressFocus.requestFocus();
      return;
    }
    if (!_isAddressAllowed(address)) {
      setState(() => _error = l10n.serverInvalidAddress);
      _addressFocus.requestFocus();
      return;
    }

    _submitting = true;
    widget.submitting.value = true;
    setState(() => _error = null);

    final label = _label.text.trim();
    final ServerProfileView profile;
    try {
      profile = await ref
          .read(sessionViewProvider.notifier)
          .addServer(
            label: label.isEmpty ? _hostOf(address) : label,
            address: address,
          );
    } on CoreError catch (error) {
      widget.submitting.value = false;
      if (!mounted) {
        return;
      }
      setState(() {
        _submitting = false;
        _error = describeCoreError(error);
      });
      _addressFocus.requestFocus();
      return;
    }
    ref.read(preferencesProvider.notifier).setServerIcon(profile.id, _icon);
    widget.submitting.value = false;
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(profile);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.scheme;
    final labelStyle = context.texts.bodyMedium?.copyWith(
      fontSize: 13,
      fontWeight: FontWeight.w500,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(l10n.connectAddressLabel, style: labelStyle),
            Text(' *', style: labelStyle?.copyWith(color: scheme.error)),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _address,
          focusNode: _addressFocus,
          autofocus: true,
          autocorrect: false,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.next,
          onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
          onChanged: (_) {
            if (_error != null) {
              setState(() => _error = null);
            }
          },
          style: context.texts.bodyMedium?.copyWith(
            fontFeatures: tabularFigures,
          ),
          decoration: InputDecoration(
            hintText: l10n.connectAddressHint,
            errorText: _error,
          ),
        ),
        const SizedBox(height: 16),
        Text(l10n.serverLabelField, style: labelStyle),
        const SizedBox(height: 6),
        TextField(
          controller: _label,
          autocorrect: false,
          textInputAction: TextInputAction.done,
          onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
          onSubmitted: (_) => submit(),
          decoration: InputDecoration(hintText: l10n.serverLabelHint),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            ExpressiveFrame(
              size: 44,
              shapeSeed: _icon.index,
              child: Icon(_icon.icon, color: context.scheme.onPrimaryContainer),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(_icon.label(l10n), style: context.texts.bodyMedium),
            ),
            TextButton(
              onPressed: _submitting
                  ? null
                  : () async {
                      final icon = await showServerIconPicker(context, _icon);
                      if (icon != null && mounted) setState(() => _icon = icon);
                    },
              child: Text(l10n.serverIconChange),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// 没填备注名时用地址的主机名兜底，列表里不会出现一长串 `host:port`。
String _hostOf(String address) {
  final withoutScheme = address.contains('://')
      ? address.split('://').last
      : address;
  final host = withoutScheme.split(':').first;
  return host.isEmpty ? address : host;
}

/// UI 只负责挡住裸昵称和明显错误的格式；官方域名由 Rust 的最终出口拒绝。
bool _isAddressAllowed(String raw) {
  final address = raw.trim();
  if (address.isEmpty ||
      address.contains(RegExp(r'\s')) ||
      address.contains('://')) {
    return false;
  }

  if (address.startsWith('[')) {
    final end = address.indexOf(']');
    if (end <= 1 || !_isIpv6(address.substring(1, end))) {
      return false;
    }
    final tail = address.substring(end + 1);
    if (tail.isEmpty) {
      return true;
    }
    return tail.startsWith(':') && _validPort(tail.substring(1));
  }

  final colon = address.lastIndexOf(':');
  if (colon >= 0) {
    final host = address.substring(0, colon);
    return !host.contains(':') &&
        _validPort(address.substring(colon + 1)) &&
        _validHost(host);
  }
  return _validHost(address);
}

bool _validHost(String host) {
  if (host.isEmpty) {
    return false;
  }
  if (host.toLowerCase() == 'localhost' || _isIpv4(host)) {
    return true;
  }
  if (!host.contains('.')) {
    return false;
  }
  final labels =
      (host.endsWith('.') ? host.substring(0, host.length - 1) : host).split(
        '.',
      );
  if (labels.length < 2) {
    return false;
  }
  return labels.every(
    (label) =>
        label.isNotEmpty &&
        label.length <= 63 &&
        RegExp(r'^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$').hasMatch(label),
  );
}

bool _isIpv4(String host) {
  final parts = host.split('.');
  if (parts.length != 4) {
    return false;
  }
  return parts.every((part) {
    final value = int.tryParse(part);
    return part.isNotEmpty &&
        part.length <= 3 &&
        value != null &&
        value >= 0 &&
        value <= 255;
  });
}

bool _isIpv6(String host) {
  try {
    return Uri.parse('http://[$host]').host == host;
  } on FormatException {
    return false;
  }
}

bool _validPort(String raw) {
  final port = int.tryParse(raw);
  return port != null && port >= 1 && port <= 65535;
}
