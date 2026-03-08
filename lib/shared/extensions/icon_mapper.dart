import 'package:flutter/material.dart';

class IconMapper {
  const IconMapper._();

  static const Map<String, IconData> _map = <String, IconData>{
    'movie': Icons.movie,
    'sports_esports': Icons.sports_esports,
    'chat': Icons.chat,
    'call_end': Icons.call_end,
    'radio_button_checked': Icons.radio_button_checked,
    'stop_circle': Icons.stop_circle,
    'fiber_manual_record': Icons.fiber_manual_record,
    'stop': Icons.stop,
    'bolt': Icons.bolt,
    'mic': Icons.mic,
    'volume_up': Icons.volume_up,
    'music_note': Icons.music_note,
    'campaign': Icons.campaign,
    'forum': Icons.forum,
    'videocam': Icons.videocam,
    'notifications': Icons.notifications,
    'tv_off': Icons.tv_off,
    'volume_off': Icons.volume_off,
    'layers_clear': Icons.layers_clear,
    'settings': Icons.settings,
    'play_arrow': Icons.play_arrow,
  };

  static IconData fromName(String name) {
    return _map[name] ?? Icons.touch_app;
  }

  static List<String> availableIcons() => _map.keys.toList(growable: false);
}
