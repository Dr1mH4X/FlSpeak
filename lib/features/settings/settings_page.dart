import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flspeak_ffi/flspeak_ffi.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

final packageInfoProvider = FutureProvider<PackageInfo>(
  (ref) => PackageInfo.fromPlatform(),
);

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final version = ref.watch(packageInfoProvider).value?.version ?? '…';
    final storePath = ref.watch(storePathProvider);
    final locale = ref.watch(localeProvider);
    final scheme = Theme.of(context).colorScheme;

    return PaneShell(
      title: l10n.settingsTitle,
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              SectionHeader(label: l10n.settingsLocale),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: 'system',
                      label: Text(l10n.settingsLocaleSystem),
                    ),
                    const ButtonSegment(value: 'en', label: Text('English')),
                    const ButtonSegment(value: 'zh', label: Text('中文')),
                  ],
                  selected: {_localeKey(locale)},
                  onSelectionChanged: (selection) => ref
                      .read(localeProvider.notifier)
                      .update(_localeFor(selection.first)),
                ),
              ),
              const SizedBox(height: 20),
              _SettingRow(
                icon: Icons.info_outline_rounded,
                title: l10n.settingsVersion,
                value: version,
              ),
              _SettingRow(
                icon: Icons.folder_outlined,
                title: l10n.settingsStorePath,
                value: storePath,
              ),
              SectionHeader(label: l10n.complianceTitle),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  l10n.compliancePolicy,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: 16),
              const _AddressChecker(),
              SectionHeader(label: l10n.settingsAudioTitle),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  l10n.voiceRustNote,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _localeKey(Locale? locale) => switch (locale?.languageCode) {
  'en' => 'en',
  'zh' => 'zh',
  _ => 'system',
};

Locale? _localeFor(String key) => switch (key) {
  'en' => const Locale('en'),
  'zh' => const Locale('zh'),
  _ => null,
};

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 12),
          SizedBox(width: 140, child: Text(title, style: text.bodyMedium)),
          Expanded(
            child: SelectableText(
              value,
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// 直接把 T1 校验暴露给用户，方便解释「为什么这个地址连不上」。
class _AddressChecker extends StatefulWidget {
  const _AddressChecker();

  @override
  State<_AddressChecker> createState() => _AddressCheckerState();
}

class _AddressCheckerState extends State<_AddressChecker> {
  final _address = TextEditingController();
  String? _result;
  bool _denied = false;

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  void _check() {
    final l10n = AppLocalizations.of(context);
    try {
      final profile = validateServerAddress(address: _address.text.trim());
      setState(() {
        _denied = false;
        _result = '${l10n.settingsValidateOk} ${profile.host}:${profile.port}';
      });
    } on CoreError catch (error) {
      setState(() {
        _denied = true;
        _result = describeCoreError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.settingsValidateTitle, style: text.titleSmall),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _address,
                  autocorrect: false,
                  decoration: InputDecoration(
                    hintText: l10n.settingsValidateHint,
                    isDense: true,
                  ),
                  onSubmitted: (_) => _check(),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: _check,
                child: Text(l10n.settingsValidate),
              ),
            ],
          ),
          if (_result != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  _denied
                      ? Icons.block_rounded
                      : Icons.check_circle_outline_rounded,
                  size: 16,
                  color: _denied ? context.status.deny : context.status.live,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: SelectableText(
                    _result!,
                    style: text.bodySmall?.copyWith(
                      color: _denied ? context.status.deny : scheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
