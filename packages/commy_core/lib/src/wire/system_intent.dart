import 'dart:convert';

import 'package:commy_core/src/wire/wire_json.dart';
import 'package:commy_core/src/wire/wire_keys.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter/foundation.dart';

/// What kind of thing the Android system handed the app.
enum SystemIntentKind {
  /// A protocol or subscription link the user tapped somewhere else.
  link(wireName: 'link'),

  /// A configuration file opened from a file manager or a chat.
  file(wireName: 'file'),

  /// Plain text shared into Commy.
  text(wireName: 'text'),

  /// "Connect", asked for from outside the UI — the Quick Settings tile.
  connect(wireName: 'connect');

  const SystemIntentKind({required this.wireName});

  /// Value carried on the wire.
  final String wireName;
}

/// One event off the `dev.commy.app/intents` channel.
///
/// This channel is not part of the tunnel protocol and Kotlin says so: a deep
/// link, a shared file and a tile tap are inputs from the operating system,
/// not tunnel state. It stayed unread for a while, and the cost was specific —
/// the manifest registers Commy as a handler for `vless://`, `vmess://`,
/// `trojan://`, `ss://`, `hysteria2://`, `tuic://`, JSON and YAML files and
/// shared text, so the app appears in "Open with" and then did nothing at all.
@immutable
class SystemIntent {
  /// Creates an event.
  const SystemIntent({required this.kind, this.uri, this.text});

  /// Reads one, or returns `null` for a payload this version does not know.
  ///
  /// Lenient on purpose: an unknown `kind` from a newer native side must be
  /// skipped, never thrown, because this arrives on a stream that nothing is
  /// in a position to catch.
  static SystemIntent? tryParse(String payload) {
    final JsonMap? json;
    try {
      json = WireJson.asMap(jsonDecode(payload));
    } on FormatException {
      return null;
    }
    if (json == null) {
      return null;
    }
    final raw = json[WireKeys.kind];
    if (raw is! String) {
      return null;
    }
    for (final kind in SystemIntentKind.values) {
      if (kind.wireName != raw) {
        continue;
      }
      final uri = json[WireKeys.uri];
      final text = json[WireKeys.text];
      return SystemIntent(
        kind: kind,
        uri: uri is String && uri.isNotEmpty ? uri : null,
        text: text is String && text.isNotEmpty ? text : null,
      );
    }
    return null;
  }

  /// What arrived.
  final SystemIntentKind kind;

  /// The link or the file location, for [SystemIntentKind.link] and
  /// [SystemIntentKind.file].
  final String? uri;

  /// The shared text, for [SystemIntentKind.text].
  final String? text;

  /// Whatever the user actually handed over, link or text.
  String? get payload => uri ?? text;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SystemIntent &&
          other.kind == kind &&
          other.uri == uri &&
          other.text == text;

  @override
  int get hashCode => Object.hash(kind, uri, text);

  /// Never prints [uri] or [text]: a `vless://` link carries the user's UUID
  /// and this object ends up in bug reports (rule R3).
  @override
  String toString() => 'SystemIntent(${kind.wireName})';
}
