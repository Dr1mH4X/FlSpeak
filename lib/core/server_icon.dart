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
