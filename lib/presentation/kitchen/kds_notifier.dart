library teashop_pos.presentation.kitchen.kds_notifier;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../client/waiter_api_service.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/order.dart';

/// Holds the live order list for the Kitchen Display and polls the Admin Host.
class KdsNotifier extends ChangeNotifier {
  KdsNotifier(this._api);
  final WaiterApiService _api;

  List<Order> _orders = [];
  bool _loading = false;
  String? _error;
  DateTime? _lastPoll;
  Timer? _timer;
  bool _disposed = false;

  List<Order> get orders => _orders;
  bool get loading => _loading;
  String? get error => _error;
  DateTime? get lastPoll => _lastPoll;

  List<Order> get pendingOrders =>
      _orders.where((o) => o.status == AppConstants.statusPending).toList();
  List<Order> get preparingOrders =>
      _orders.where((o) => o.status == AppConstants.statusPreparing).toList();
  List<Order> get readyOrders =>
      _orders.where((o) => o.status == AppConstants.statusReady).toList();

  /// Notifies listeners only while the notifier is still alive.
  ///
  /// `poll()` is asynchronous: an in-flight fetch can complete *after* the
  /// owning widget has called [dispose] (e.g. on navigation away or on
  /// reconnect). Calling `notifyListeners()` on a disposed `ChangeNotifier`
  /// throws "A KdsNotifier was used after being disposed", so every notification
  /// is guarded by the [_disposed] flag.
  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  /// Fetch the latest orders from the Admin Host.
  Future<void> poll() async {
    if (_loading || _disposed) return;
    _loading = true;
    _safeNotify();
    try {
      _error = null;
      _orders = await _api.fetchOrders()
        ..sort((a, b) {
          final aTime = a.createdAt?.millisecondsSinceEpoch ?? 0;
          final bTime = b.createdAt?.millisecondsSinceEpoch ?? 0;
          return bTime.compareTo(aTime);
        });
      _lastPoll = DateTime.now();
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      _safeNotify();
    }
  }

  /// Move an order to a new status and refresh.
  Future<void> setStatus(int orderId, String status) async {
    if (_disposed) return;
    await _api.updateOrderStatus(orderId, status);
    await poll();
  }

  void startPolling({Duration interval = AppConstants.ordersPollInterval}) {
    if (_disposed) return;
    stopPolling();
    _timer = Timer.periodic(interval, (_) => poll());
    poll();
  }

  void stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _disposed = true;
    stopPolling();
    super.dispose();
  }
}
