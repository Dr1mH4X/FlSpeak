import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

enum ServerIcon {
  community('community', Icons.groups_rounded),
  gaming('gaming', Icons.sports_esports_rounded),
  music('music', Icons.music_note_rounded),
  work('work', Icons.work_rounded),
  home('home', Icons.home_rounded),
  terminal('terminal', Icons.terminal_rounded),
  favorite('favorite', Icons.favorite_rounded),
  planet('planet', Icons.public_rounded),
  coffee('coffee', Icons.local_cafe_rounded),
  rocket('rocket', Icons.rocket_launch_rounded),
  science('science', Icons.science_rounded),
  headphones('headphones', Icons.headphones_rounded);

  const ServerIcon(this.id, this.icon);

  final String id;
  final IconData icon;

  static ServerIcon fromId(Object? id) =>
      values.firstWhere((value) => value.id == id, orElse: () => community);

  String label(AppLocalizations l10n) => switch (this) {
    community => l10n.serverIconCommunity,
    gaming => l10n.serverIconGaming,
    music => l10n.serverIconMusic,
    work => l10n.serverIconWork,
    home => l10n.homeTitle,
    terminal => l10n.serverIconTerminal,
    favorite => l10n.serverIconFavorite,
    planet => l10n.serverIconPlanet,
    coffee => l10n.serverIconCoffee,
    rocket => l10n.serverIconRocket,
    science => l10n.serverIconScience,
    headphones => l10n.settingsVoice,
  };
}

/// 服务器图标配置项：跟随服务器下发的自定义图标，或固定选用本地预设。
sealed class ServerIconChoice {
  const ServerIconChoice();

  static const ServerIconChoice auto = ServerIconAuto();

  static ServerIconChoice preset(ServerIcon icon) => ServerIconPreset(icon);

  static ServerIconChoice fromId(Object? id) {
    if (id == 'auto') return auto;
    for (final preset in ServerIcon.values) {
      if (preset.id == id) return ServerIconPreset(preset);
    }
    return auto;
  }

  String get id;
  bool get isAuto;
  ServerIcon get fallbackPreset;
  IconData get pickerIcon;
  String label(AppLocalizations l10n);
}

final class ServerIconAuto extends ServerIconChoice {
  const ServerIconAuto();

  @override
  String get id => 'auto';

  @override
  bool get isAuto => true;

  @override
  ServerIcon get fallbackPreset => ServerIcon.community;

  @override
  IconData get pickerIcon => Icons.dns_rounded;

  @override
  String label(AppLocalizations l10n) => l10n.serverIconAuto;

  @override
  bool operator ==(Object other) => other is ServerIconAuto;

  @override
  int get hashCode => id.hashCode;
}

final class ServerIconPreset extends ServerIconChoice {
  const ServerIconPreset(this.preset);

  final ServerIcon preset;

  @override
  String get id => preset.id;

  @override
  bool get isAuto => false;

  @override
  ServerIcon get fallbackPreset => preset;

  @override
  IconData get pickerIcon => preset.icon;

  @override
  String label(AppLocalizations l10n) => preset.label(l10n);

  @override
  bool operator ==(Object other) =>
      other is ServerIconPreset && other.preset == preset;

  @override
  int get hashCode => preset.hashCode;
}
