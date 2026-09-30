import 'package:commy_config/src/builder/config_platform.dart';
import 'package:commy_config/src/builder/inbound_section_builder.dart';
import 'package:commy_config/src/builder/route_matcher.dart';
import 'package:commy_config/src/builder/routing_warning.dart';
import 'package:commy_config/src/builder/routing_warning_kind.dart';
import 'package:commy_config/src/builder/sing_box_keys.dart';
import 'package:commy_config/src/builder/sing_box_tags.dart';
import 'package:commy_domain/commy_domain.dart';

/// Builds the `route` section.
///
/// Rule order is the whole meaning of this section — the first match wins — so
/// it is fixed here rather than assembled ad hoc:
///
/// 1. `sniff`, so later rules can see what the connection actually is;
/// 2. DNS hijack, so no query escapes the policy (rule R6);
/// 3. everything else sent to the tunnel's own addresses refused
///    ([ownAddressesReject]), so it cannot leave the device as a LAN
///    address;
/// 4. LAN bypass, when the user asked for it;
/// 5. ad blocking, when the user turned it on and the list is on disk — the
///    connection half of it; the query itself is refused by
///    `DnsSectionBuilder`, one layer earlier;
/// 6. per-app exclusions, where the platform expresses them as processes;
/// 7. the user's own rules, in their own order — with FakeIP on, the name
///    resolved just ahead of the first one that matches on addresses
///    ([fakeIpResolve]).
///
/// `block` is not an outbound here. The legacy `block` outbound still exists at
/// v1.13.16 but the supported spelling is `"action": "reject"`, and the `dns`
/// outbound that older configs pair with it is not registered at all — writing
/// one would fail with "unknown outbound type".
abstract final class RouteSectionBuilder {
  /// Port plain DNS uses.
  static const int dnsPort = 53;

  /// The geosite list the ad blocking feature applies.
  ///
  /// The name is the one the default source actually publishes —
  /// `geosite-category-ads-all.srs` — rather than one of ours. A tag nobody
  /// serves is a switch that can never do anything: the download answers 404,
  /// no file ever lands, and every document is built with the rule left out
  /// and a warning the user has no way to act on. A test pins this name
  /// against `AppSettings.defaultRuleSetSource` so the two cannot drift.
  static const String adsRuleSetName = 'category-ads-all';

  /// The tag both this section and the DNS section look for when ad blocking
  /// is on.
  ///
  /// Derived once, because two sections now name the same list and a document
  /// where they disagree would block the connection but still resolve the
  /// name, or the other way round.
  static final String adsRuleSetTag = SingBoxTags.geosite(adsRuleSetName);

  /// The rule that refuses whatever else is sent to the tunnel's own
  /// addresses.
  ///
  /// The VPN gives the system the address after the tunnel's own,
  /// `172.19.0.2`, as its DNS server (libbox, `GetDNSServerAddress`).
  /// Plain DNS to it is hijacked by the rules ahead of this one; anything
  /// else went on down the list, and the address is a private one. With the
  /// LAN bypass on it was dialled directly, on Wi-Fi or mobile data; with it
  /// off, through the proxy onto the server's own network. Android asks its
  /// DNS server for DNS over TLS on port 853 whenever the VPN comes up, and
  /// with Private DNS on "Automatic", the default, it checks no certificate.
  /// Anything on the physical path that answered at `172.19.0.2:853` — a
  /// Docker network on a home router or server, which is often
  /// `172.19.0.0/16`, or anyone on public Wi-Fi — would have been handed
  /// every app's queries, outside the tunnel and past the hijack,
  /// `dns-remote` and FakeIP (rule R6). Refused, the probe fails at once and
  /// Android stays on port 53, which is hijacked.
  ///
  /// The prefixes are the interface's own, host part and all: the core masks
  /// them (`netipx.RangeOfPrefix`), so the rule covers the whole `/30` and
  /// `/126` and cannot drift from the addresses the TUN is given.
  static Map<String, Object?> get ownAddressesReject => <String, Object?>{
        SingBoxKeys.ipCidr: <String>[
          InboundSectionBuilder.tunAddressV4,
          InboundSectionBuilder.tunAddressV6,
        ],
        SingBoxKeys.action: SingBoxKeys.actionReject,
      };

  /// The rule that resolves a FakeIP connection's name before the rules that
  /// look at addresses.
  ///
  /// A connection to a FakeIP address reaches the router as the name it
  /// stands for (`route/route.go`, `matchRule`), and nothing resolves that
  /// name unless a rule says so. An `ip_cidr` or `geoip` rule then has no
  /// address to look at and matches nothing: `geoip:ru` → Direct sent every
  /// such connection through the proxy, and `geoip:xx` → Block blocked none.
  /// This rule gives them the addresses, once, ahead of the first of them.
  ///
  /// The resolver is named, and it is the one through the tunnel. Unnamed,
  /// the lookup would run the DNS rules and come back from FakeIP with the
  /// same fake address; the direct resolver would ask about every name the
  /// tunnel carries outside it (rule R6). A name the tunnel's resolver cannot
  /// answer now fails its connection, where before it went on to the
  /// proxy; only connections no rule above had claimed get this far.
  ///
  /// It changes more than which rules match. A connection that holds
  /// addresses is dialled by address, whichever outbound the rules then pick
  /// (`route/conn.go`, `DialSerialNetwork`). Every connection that carries a
  /// name and gets past this rule waits for a lookup through the tunnel
  /// before it dials, unless the answer is cached. The proxy server is handed
  /// the address `dns-remote` returned, not the name, so routing by name on
  /// the server works only where the server sniffs. A Direct rule below
  /// dials the address the tunnel's resolver gave, which for a CDN may be an
  /// edge near the proxy's exit. With `geoip:ru` → Direct as the first rule,
  /// the common setup in Russia, that is every connection by name.
  ///
  /// The strategy is written here, not inherited from the DNS section
  /// ([fakeIpResolveStrategy]).
  static Map<String, Object?> fakeIpResolve(DnsStrategy chosen) =>
      <String, Object?>{
        SingBoxKeys.action: SingBoxKeys.actionResolve,
        SingBoxKeys.dnsServer: SingBoxTags.dnsRemote,
        SingBoxKeys.strategy: fakeIpResolveStrategy(chosen).wireName,
      };

  /// The address family [fakeIpResolve] asks for when the user chose
  /// [chosen] on the DNS screen: A first, unless they chose IPv6 only.
  ///
  /// Inherited, "prefer IPv6" would put the AAAA address first. VLESS, VMess
  /// and Trojan report success once the stream to the server is open, not
  /// once the server has reached the target, so the core never falls back to
  /// the A record: on a server without IPv6 every dual-stack site failed,
  /// where the server resolving the name itself would have picked what it
  /// can reach. "IPv4 only" is asked for both too: the AAAA answer only
  /// matters for a name with no A record, which the server would have
  /// reached over IPv6 by name all the same. "IPv6 only" is kept because it
  /// is a choice the user made on purpose.
  static DnsStrategy fakeIpResolveStrategy(DnsStrategy chosen) =>
      switch (chosen) {
        DnsStrategy.ipv6Only => DnsStrategy.ipv6Only,
        DnsStrategy.preferIpv4 ||
        DnsStrategy.preferIpv6 ||
        DnsStrategy.ipv4Only =>
          DnsStrategy.preferIpv4,
      };

  /// Every rule set tag [routing] would need to apply in full.
  ///
  /// The answer to "what should the rule sets screen offer to download": the
  /// tags the user's own rules name, not a catalogue of everything that
  /// exists. Sorted, so the screen renders in a stable order.
  ///
  /// Reads the same [RouteMatcher] the build does, so a rule that the builder
  /// would drop for want of a file is exactly a tag this returns.
  static List<String> requiredRuleSets({
    required RoutingPolicy routing,
    required ConfigPlatform platform,
  }) {
    final tags = <String>{
      if (routing.blockAds) adsRuleSetTag,
    };
    if (routing.mode == RoutingMode.rules) {
      for (final rule in routing.activeRules) {
        final matcher = RouteMatcher.tryParse(rule.matcher, platform: platform);
        if (matcher != null && !matcher.isEmpty) {
          tags.addAll(matcher.ruleSets);
        }
      }
    }
    return tags.toList()..sort();
  }

  /// Builds the section, appending anything it had to drop to [warnings].
  ///
  /// [dns] is the policy the DNS section is built from: whether it answers
  /// with FakeIP addresses, and the address family the user chose.
  static Map<String, Object?> build({
    required RoutingPolicy routing,
    required ConfigPlatform platform,
    required Set<String> availableRuleSets,
    required String? ruleSetDirectory,
    required DnsSettings dns,
    required List<RoutingWarning> warnings,
  }) {
    final usedRuleSets = <String>{};
    final rules = <Map<String, Object?>>[
      <String, Object?>{SingBoxKeys.action: SingBoxKeys.actionSniff},
      <String, Object?>{
        SingBoxKeys.protocol: SingBoxKeys.protocolDns,
        SingBoxKeys.action: SingBoxKeys.actionHijackDns,
      },
      <String, Object?>{
        SingBoxKeys.port: <int>[dnsPort],
        SingBoxKeys.action: SingBoxKeys.actionHijackDns,
      },
      // Whether or not the LAN is bypassed: through the proxy the same
      // address is the server's own network.
      ownAddressesReject,
    ];

    if (routing.bypassLan) {
      rules.add(<String, Object?>{
        SingBoxKeys.ipIsPrivate: true,
        SingBoxKeys.outbound: SingBoxTags.direct,
      });
    }

    if (routing.blockAds) {
      final tag = adsRuleSetTag;
      if (availableRuleSets.contains(tag)) {
        usedRuleSets.add(tag);
        rules.add(<String, Object?>{
          SingBoxKeys.ruleSet: <String>[tag],
          SingBoxKeys.action: SingBoxKeys.actionReject,
        });
      } else {
        warnings.add(
          RoutingWarning(RoutingWarningKind.adBlockListMissing, tag),
        );
      }
    }

    rules.addAll(
      _perAppRules(
        routing: routing,
        platform: platform,
        warnings: warnings,
      ),
    );

    if (routing.mode == RoutingMode.rules) {
      var resolved = !dns.fakeIp;
      for (final rule in routing.activeRules) {
        final matcher = RouteMatcher.tryParse(rule.matcher, platform: platform);
        if (matcher == null || matcher.isEmpty) {
          warnings.add(
            RoutingWarning(RoutingWarningKind.ruleNotApplicable, rule.matcher),
          );
          continue;
        }
        final missing = matcher.ruleSets.difference(availableRuleSets);
        if (missing.isNotEmpty) {
          warnings.add(
            RoutingWarning(
              RoutingWarningKind.ruleSetsMissing,
              rule.matcher,
              missing: missing.toList()..sort(),
            ),
          );
          continue;
        }
        usedRuleSets.addAll(matcher.ruleSets);
        if (!resolved && matcher.needsResolvedAddress) {
          rules.add(fakeIpResolve(dns.strategy));
          resolved = true;
        }
        rules.add(<String, Object?>{
          ...matcher.fields,
          ..._action(rule.action),
        });
      }
    }

    final ruleSets = <Map<String, Object?>>[
      for (final tag in usedRuleSets.toList()..sort())
        <String, Object?>{
          SingBoxKeys.type: SingBoxKeys.typeLocal,
          SingBoxKeys.tag: tag,
          SingBoxKeys.format: SingBoxKeys.formatBinary,
          SingBoxKeys.ruleSetPath:
              '$ruleSetDirectory/${SingBoxTags.ruleSetFileName(tag)}',
        },
    ];

    return <String, Object?>{
      SingBoxKeys.rules: rules,
      if (ruleSets.isNotEmpty) SingBoxKeys.ruleSet: ruleSets,
      SingBoxKeys.autoDetectInterface: true,
      // The proxy server's own hostname has to be resolved outside the tunnel:
      // the tunnel is not up yet when that dial happens.
      SingBoxKeys.defaultDomainResolver: <String, Object?>{
        SingBoxKeys.dnsServer: SingBoxTags.dnsDirect,
      },
      SingBoxKeys.finalTag: finalOutbound(routing.mode),
    };
  }

  /// The outbound everything unmatched ends up in.
  static String finalOutbound(RoutingMode mode) => switch (mode) {
        RoutingMode.global => SingBoxTags.proxyGroup,
        RoutingMode.rules => SingBoxTags.proxyGroup,
        RoutingMode.direct => SingBoxTags.direct,
      };

  static Map<String, Object?> _action(RuleAction action) => switch (action) {
        RuleAction.proxy => <String, Object?>{
            SingBoxKeys.outbound: SingBoxTags.proxyGroup,
          },
        RuleAction.direct => <String, Object?>{
            SingBoxKeys.outbound: SingBoxTags.direct,
          },
        RuleAction.block => <String, Object?>{
            SingBoxKeys.action: SingBoxKeys.actionReject,
          },
      };

  static List<Map<String, Object?>> _perAppRules({
    required RoutingPolicy routing,
    required ConfigPlatform platform,
    required List<RoutingWarning> warnings,
  }) {
    if (routing.perAppMode == PerAppMode.disabled ||
        routing.perAppPackages.isEmpty ||
        platform.supportsPackageRules) {
      // Android expresses this on the TUN inbound instead, which is where the
      // core wants it (docs/13-libbox-reference.md, TunOptions).
      return const <Map<String, Object?>>[];
    }
    if (!platform.supportsProcessRules) {
      warnings.add(
        RoutingWarning(RoutingWarningKind.perAppUnavailable, platform.name),
      );
      return const <Map<String, Object?>>[];
    }
    final identifiers = <String>[
      for (final item in routing.perAppPackages)
        if (item.trim().isNotEmpty) item.trim(),
    ];
    if (routing.perAppMode == PerAppMode.include) {
      // "Only these apps" would mean flipping the final action, which silently
      // rewrites what every other rule means. Refusing is the honest answer.
      warnings.add(
        RoutingWarning(RoutingWarningKind.perAppIncludeOnly, platform.name),
      );
      return const <Map<String, Object?>>[];
    }
    return <Map<String, Object?>>[
      <String, Object?>{
        SingBoxKeys.processName: identifiers,
        SingBoxKeys.outbound: SingBoxTags.direct,
      },
    ];
  }
}
