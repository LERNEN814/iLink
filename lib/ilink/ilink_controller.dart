import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:luci_mobile/ilink/ilink_api.dart';
import 'package:luci_mobile/ilink/ilink_feature_models.dart';
import 'package:luci_mobile/ilink/ilink_models.dart';

final iLinkProvider = ChangeNotifierProvider<ILinkController>(
  (ref) => ILinkController(),
);

class ILinkController extends ChangeNotifier {
  ILinkController({ILinkGatewayClient? client})
    : _client = client ?? ILinkGatewayClient();

  static const _profileKey = 'ilink.profile.v1';
  static const _themeKey = 'ilink.theme.v1';
  static const _glassKey = 'ilink.glass.v1';
  static const _storage = FlutterSecureStorage();

  final ILinkGatewayClient _client;
  ILinkGatewayClient get client => _client;

  // Page data outlives the page: switching tabs must not refetch everything.
  OpenClashData? openClash;
  DateTime? openClashAt;
  List<ProxyConnection>? connections;
  DateTime? connectionsAt;

  /// Last fetched subscription usage per config, kept until refreshed again.
  final Map<String, SubscriptionUsage> quota = {};
  DateTime? quotaAt;

  void cacheQuota(String name, SubscriptionUsage usage) {
    quota[name] = usage;
    quotaAt = DateTime.now();
  }

  bool isFresh(DateTime? at, Duration ttl) =>
      at != null && DateTime.now().difference(at) < ttl;

  void cacheOpenClash(OpenClashData value) {
    openClash = value;
    openClashAt = DateTime.now();
  }

  void cacheConnections(List<ProxyConnection> value) {
    connections = value;
    connectionsAt = DateTime.now();
  }

  ILinkProfile? profile;
  ILinkData? data;
  bool initialized = false;
  bool loading = false;
  bool refreshing = false;
  bool editing = false;
  String? error;
  int themeIndex = 0;
  bool glassEnabled = true;

  Future<void> initialize() async {
    try {
      themeIndex =
          int.tryParse(await _storage.read(key: _themeKey) ?? '0') ?? 0;
      glassEnabled = await _storage.read(key: _glassKey) != 'false';
      final raw = await _storage.read(key: _profileKey);
      if (raw != null) profile = ILinkProfile.fromJson(jsonDecode(raw));
    } catch (exception) {
      error = exception.toString();
    } finally {
      initialized = true;
      notifyListeners();
    }
    // Load in the background so the shell appears immediately.
    // Non-silent so the shell shows a spinner instead of a stale error state.
    if (profile != null) unawaited(refresh());
  }

  Future<bool> save(ILinkProfile value) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final result = await _client.load(value);
      await _storage.write(key: _profileKey, value: jsonEncode(value.toJson()));
      profile = value;
      data = result;
      editing = false;
      return true;
    } catch (exception) {
      error = exception.toString();
      return false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> refresh({bool silent = false}) async {
    final current = profile;
    if (current == null || refreshing) return;
    refreshing = true;
    if (!silent) {
      loading = true;
      error = null;
    }
    notifyListeners();
    try {
      data = await _client.load(current);
      error = null;
    } catch (exception) {
      error = exception.toString();
    } finally {
      refreshing = false;
      loading = false;
      notifyListeners();
    }
  }

  void startEditing() {
    editing = true;
    error = null;
    notifyListeners();
  }

  void cancelEditing() {
    editing = false;
    error = null;
    notifyListeners();
  }

  Future<void> clear() async {
    await _storage.delete(key: _profileKey);
    profile = null;
    data = null;
    openClash = null;
    openClashAt = null;
    connections = null;
    connectionsAt = null;
    quota.clear();
    quotaAt = null;
    error = null;
    editing = false;
    notifyListeners();
  }

  Future<void> cycleTheme() async {
    themeIndex = (themeIndex + 1) % 3;
    await _storage.write(key: _themeKey, value: '$themeIndex');
    notifyListeners();
  }

  Future<void> toggleGlass() async {
    glassEnabled = !glassEnabled;
    await _storage.write(key: _glassKey, value: '$glassEnabled');
    notifyListeners();
  }
}
