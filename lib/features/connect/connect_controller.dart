import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/rest_client.dart';
import '../../core/models/session.dart';

class ConnectState {
  const ConnectState({
    this.checking = false,
    this.health,
    this.error,
    this.checkedAt,
  });

  final bool checking;
  final HealthInfo? health;
  final String? error;
  final DateTime? checkedAt;
}

class ConnectController extends Notifier<ConnectState> {
  @override
  ConnectState build() => const ConnectState();

  Future<void> check() async {
    state = const ConnectState(checking: true);
    try {
      final health = await ref.read(restClientProvider).health();
      state = ConnectState(health: health, checkedAt: DateTime.now());
    } on TimeoutException {
      state = ConnectState(error: '응답 없음 (시간 초과)', checkedAt: DateTime.now());
    } catch (e) {
      state = ConnectState(error: e.toString(), checkedAt: DateTime.now());
    }
  }
}

final connectControllerProvider =
    NotifierProvider<ConnectController, ConnectState>(ConnectController.new);
