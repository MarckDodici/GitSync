import 'package:flutter/foundation.dart';

enum GhSponsorCheck { sponsor, notSponsor, notLinked, tokenRejected, unreachable }

/// Fork build: all features are always available. No sponsor lookup, no network
/// calls and no removal of extra repositories. Public API kept so existing callers compile unchanged.
class PremiumManager {
  final ValueNotifier<bool?> hasPremiumNotifier = ValueNotifier(true);

  Future<void> init() async {
    hasPremiumNotifier.value = true;
  }

  Future<GhSponsorCheck> updateGitHubSponsorPremium() async {
    hasPremiumNotifier.value = true;
    return GhSponsorCheck.sponsor;
  }

  Future<bool> cullNonPremium() async => false;

  void dispose() {
    hasPremiumNotifier.dispose();
  }
}
