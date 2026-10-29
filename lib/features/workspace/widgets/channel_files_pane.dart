import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models.dart';
import '../../../core/notices.dart';
import '../../../core/providers.dart';
import '../../../l10n/app_localizations.dart';

class ChannelFilesPane extends ConsumerStatefulWidget {
  const ChannelFilesPane({required this.channelId, super.key});
  final int channelId;
  @override
  ConsumerState<ChannelFilesPane> createState() => _ChannelFilesPaneState();
}

class _ChannelFilesPaneState extends ConsumerState<ChannelFilesPane> {
  final _password = TextEditingController();
  String _path = '/';
  List<ChannelFileView> _files = [];
  bool _loading = true;
  bool _failed = false;
  bool _passwordRequired = false;
  bool _downloading = false;
  int? _transferId;
  int _loadRevision = 0;
  late final _epoch = ref.read(sessionViewProvider).connectionEpoch;
  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  bool get _available {
    final view = ref.read(sessionViewProvider);
    return view.connected && view.connectionEpoch == _epoch;
  }

  Future<void> _load() async {
    if (!mounted || !_available) return;
    final revision = ++_loadRevision;
    bool current() => mounted && _available && revision == _loadRevision;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final files = await ref
          .read(coreSessionProvider)
          .listFiles(
            channelId: widget.channelId,
            path: _path,
            password: _password.text,
          );
      if (current()) {
        setState(() {
          _files = List<ChannelFileView>.of(files)
            ..sort(
              (a, b) => a.directory == b.directory
                  ? a.name.compareTo(b.name)
                  : a.directory
                  ? -1
                  : 1,
            );
          _passwordRequired = false;
        });
      }
    } on CoreError_ChannelPasswordRequired {
      if (current()) setState(() => _passwordRequired = true);
    } on CoreError catch (error) {
      if (mounted && current()) {
        setState(() => _failed = true);
        ref
            .read(noticeCenterProvider.notifier)
            .show(describeCoreError(error, AppLocalizations.of(context)));
      }
    } finally {
      if (current()) setState(() => _loading = false);
    }
  }

  Future<void> _download(ChannelFileView file) async {
    final view = ref.read(sessionViewProvider);
    if (_downloading ||
        view.activeFileDownloads.containsKey((_epoch, widget.channelId)) ||
        !_available) {
      return;
    }
    setState(() {
      _downloading = true;
      _transferId = null;
    });
    try {
      await ref
          .read(sessionViewProvider.notifier)
          .saveChannelFile(
            widget.channelId,
            file.path,
            file.name,
            password: _password.text,
            onStarted: (id) {
              if (mounted) setState(() => _transferId = id);
            },
          );
    } on CoreError_ChannelPasswordRequired {
      if (mounted) setState(() => _passwordRequired = true);
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final view = ref.watch(sessionViewProvider);
    final downloading =
        _downloading ||
        view.activeFileDownloads.containsKey((_epoch, widget.channelId));
    final transferId =
        _transferId ?? view.activeFileDownloads[(_epoch, widget.channelId)];
    final transfer = view.transfers[transferId];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              IconButton(
                onPressed: _path == '/' || _loading || downloading
                    ? null
                    : () {
                        setState(
                          () => _path =
                              _path.substring(0, _path.lastIndexOf('/')).isEmpty
                              ? '/'
                              : _path.substring(0, _path.lastIndexOf('/')),
                        );
                        _load();
                      },
                icon: Icon(
                  Icons.arrow_upward_rounded,
                  semanticLabel: l10n.fileParent,
                ),
              ),
              Expanded(
                child: Text(
                  _path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                onPressed: _loading || downloading ? null : _load,
                icon: Icon(
                  Icons.refresh_rounded,
                  semanticLabel: l10n.commonRetry,
                ),
              ),
            ],
          ),
        ),
        if (_passwordRequired)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _password,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: l10n.channelPasswordLabel,
                    ),
                    onSubmitted: (_) => _load(),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _loading ? null : _load,
                  child: Text(l10n.fileUnlock),
                ),
              ],
            ),
          ),
        if (_loading || downloading)
          LinearProgressIndicator(
            value: downloading && transfer != null && transfer.total > 0
                ? transfer.transferred / transfer.total
                : null,
          ),
        Expanded(
          child: _loading
              ? const SizedBox.shrink()
              : _passwordRequired
              ? Center(child: Text(l10n.channelPasswordTitle))
              : _failed
              ? Center(
                  child: TextButton(
                    onPressed: _load,
                    child: Text(l10n.commonRetry),
                  ),
                )
              : _files.isEmpty
              ? Center(child: Text(l10n.fileListEmpty))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _files.length,
                  itemBuilder: (context, index) {
                    final file = _files[index];
                    return ListTile(
                      leading: Icon(
                        file.directory
                            ? Icons.folder_outlined
                            : Icons.insert_drive_file_outlined,
                      ),
                      title: Text(file.name),
                      subtitle: file.directory
                          ? null
                          : Text(l10n.fileSizeBytes(file.size)),
                      onTap: file.directory && !downloading
                          ? () {
                              setState(() => _path = file.path);
                              _load();
                            }
                          : null,
                      trailing: file.directory
                          ? null
                          : IconButton(
                              onPressed: downloading || !_available
                                  ? null
                                  : () => _download(file),
                              icon: Icon(
                                Icons.download_rounded,
                                semanticLabel: l10n.fileDownload,
                              ),
                            ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
