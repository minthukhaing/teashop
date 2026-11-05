// Unit tests for KdsNotifier, focusing on the "used after being disposed"
// race condition that occurs when an in-flight poll() completes after the
// notifier (and its owning widget) has been disposed.
//
// Run with:  flutter test test/kds_notifier_test.dart

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teashop_pos/client/waiter_api_service.dart';
import 'package:teashop_pos/core/constants/app_constants.dart';
import 'package:teashop_pos/data/models/order.dart';
import 'package:teashop_pos/presentation/kitchen/kds_notifier.dart';

/// A controllable fake of [WaiterApiService] used to reproduce the async gap
/// inside `poll()`.
///
/// [fetchOrdersCompleter] lets the test decide *when* the in-flight fetch
/// resolves, so we can call `dispose()` while `poll()` is still awaiting and
/// then complete the fetch afterwards -- exactly the sequence that triggered
/// "A KdsNotifier was used after being disposed".
class _FakeWaiterApi extends WaiterApiService {
  _FakeWaiterApi() : super(baseUrl: 'http://localhost:8080');

  /// Orders that will be returned once [fetchOrdersCompleter] completes.
  List<Order> ordersToReturn = [];

  /// Completer that gates every `fetchOrders()` call. The test completes it to
  /// release the in-flight poll.
  Completer<void>? fetchOrdersCompleter;

  /// Number of times `fetchOrders()` was invoked.
  int fetchOrdersCallCount = 0;

  /// Number of times `updateOrderStatus()` was invoked.
  int updateStatusCallCount = 0;

  @override
  Future<List<Order>> fetchOrders({String? status, String? since}) async {
    fetchOrdersCallCount++;
    final completer = fetchOrdersCompleter ?? Completer<void>();
    await completer.future;
    return List<Order>.from(ordersToReturn);
  }

  @override
  Future<void> updateOrderStatus(int orderId, String status) async {
    updateStatusCallCount++;
  }
}

Order _order({int? id, String status = AppConstants.statusPending}) {
  return Order(
    id: id,
    tableNumber: '1',
    status: status,
    total: 10,
    createdAt: DateTime(2024, 1, 1, 12, 0, id ?? 0),
  );
}

void main() {
  group('KdsNotifier dispose-during-poll safety', () {
    test(
        'poll() completing after dispose() does NOT throw '
        '"used after being disposed"', () async {
      final api = _FakeWaiterApi();
      api.ordersToReturn = [_order(id: 1), _order(id: 2)];
      // Gate the fetch so poll() blocks on the await.
      api.fetchOrdersCompleter = Completer<void>();

      final notifier = KdsNotifier(api);
      final pollFuture = notifier.poll(); // now awaiting fetchOrders()

      // Simulate the widget being torn down while the fetch is in flight.
      notifier.dispose();

      // Releasing the in-flight fetch must not throw. Before the fix this is
      // exactly where "A KdsNotifier was used after being disposed" fired.
      api.fetchOrdersCompleter!.complete();
      await expectLater(pollFuture, completes);
      // Notifier is already disposed above; calling dispose() again would
      // itself throw, so we deliberately do not re-dispose here.
    });

    test('a Timer.periodic tick landing after dispose() is a no-op', () async {
      final api = _FakeWaiterApi();
      api.ordersToReturn = [_order(id: 1)];
      // Never complete: keep the first poll suspended so the timer is armed.
      api.fetchOrdersCompleter = Completer<void>();

      final notifier = KdsNotifier(api);
      // Use a very short interval so a tick would fire quickly if unguarded.
      notifier.startPolling(interval: const Duration(milliseconds: 20));

      // Dispose immediately; any scheduled timer tick must be harmless.
      notifier.dispose();

      // Wait long enough for at least one tick to have been scheduled.
      await Future<void>.delayed(const Duration(milliseconds: 60));

      // No further fetches should have been started beyond the initial poll.
      expect(api.fetchOrdersCallCount, 1);
    });

    test('setStatus() called after dispose() is a no-op', () async {
      final api = _FakeWaiterApi();
      final notifier = KdsNotifier(api);
      notifier.dispose();

      await expectLater(
        notifier.setStatus(1, AppConstants.statusPreparing),
        completes,
      );
      expect(api.updateStatusCallCount, 0);
    });

    test('startPolling() called after dispose() is a no-op', () async {
      final api = _FakeWaiterApi();
      final notifier = KdsNotifier(api);
      notifier.dispose();

      notifier.startPolling();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(api.fetchOrdersCallCount, 0);
    });
  });

  group('KdsNotifier normal operation', () {
    test('poll() updates orders and notifies listeners while alive', () async {
      final api = _FakeWaiterApi();
      api.ordersToReturn = [
        _order(id: 2, status: AppConstants.statusPreparing),
        _order(id: 1, status: AppConstants.statusPending),
      ];
      api.fetchOrdersCompleter = Completer<void>();

      final notifier = KdsNotifier(api);
      var notifyCount = 0;
      notifier.addListener(() => notifyCount++);

      final pollFuture = notifier.poll();
      // First notify (loading = true) happens synchronously inside poll().
      expect(notifyCount, 1);
      expect(notifier.loading, isTrue);

      api.fetchOrdersCompleter!.complete();
      await pollFuture;

      // Second notify (loading = false) after the fetch resolves.
      expect(notifyCount, 2);
      expect(notifier.loading, isFalse);
      expect(notifier.error, isNull);
      // Orders are sorted newest-first by createdAt.
      expect(notifier.orders.map((o) => o.id), [2, 1]);
      expect(notifier.pendingOrders.length, 1);
      expect(notifier.preparingOrders.length, 1);

      notifier.dispose();
    });

    test('poll() captures errors without throwing and keeps listeners informed',
        () async {
      final api = _FakeWaiterApi();
      api.fetchOrdersCompleter = Completer<void>();

      final notifier = KdsNotifier(api);
      var notifyCount = 0;
      notifier.addListener(() => notifyCount++);

      // Make the fetch fail by completing with an error.
      final pollFuture = notifier.poll();
      api.fetchOrdersCompleter!.completeError(Exception('server down'));
      await pollFuture;

      expect(notifier.error, isNotNull);
      expect(notifier.loading, isFalse);
      expect(notifyCount, 2);

      notifier.dispose();
    });
  });
}
