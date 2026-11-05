library teashop_pos.core.network;

import 'dart:io';

/// Resolves the local machine's IPv4 address on the current network.
///
/// This lets Waiter and Kitchen clients locate the Admin Host over a local
/// Wi-Fi network without any internet access. We enumerate the host's network
/// interfaces and prefer a physical Wi-Fi / Ethernet adapter, skipping virtual
/// adapters (VirtualBox host-only, VPN tunnels, WSL, Docker, etc.) that would
/// otherwise shadow the real LAN address.
class LocalIpResolver {
  LocalIpResolver._();

  static const List<String> _virtualNameHints = [
    'virtual',
    'vbox',
    'vmware',
    'docker',
    'wsl',
    'tap',
    'outline',
    'loopback',
    'pseudo',
    'hamachi',
    'tun',
  ];

  static bool _isVirtualInterface(String name) {
    final lower = name.toLowerCase();
    return _virtualNameHints.any(lower.contains);
  }

  /// Attempts to determine the local non-loopback IPv4 address.
  ///
  /// Returns `null` when the address cannot be determined automatically (for
  /// example, when there is no active network interface). Callers should allow
  /// the operator to enter the Admin Host IP manually in that case.
  static Future<String?> getLocalIpAddress() async {
    // Strategy 1: enumerate IPv4 interfaces directly, skipping virtual adapters
    // (VirtualBox, VPN tunnels, etc.) that would otherwise shadow the real LAN.
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      // Prefer physical Wi-Fi / Ethernet adapters.
      final physical = <NetworkInterface>[];
      for (final iface in interfaces) {
        if (_isVirtualInterface(iface.name)) continue;
        physical.add(iface);
      }
      // If every adapter looked virtual, fall back to all of them.
      final candidates = physical.isNotEmpty ? physical : interfaces;

      // Prefer Wi-Fi, then Ethernet, then anything else.
      int priority(NetworkInterface i) {
        final n = i.name.toLowerCase();
        if (n.contains('wi-fi') || n.contains('wifi') || n.contains('wlan')) {
          return 0;
        }
        if (n.contains('ethernet') || n.contains('eth')) return 1;
        return 2;
      }

      candidates.sort((a, b) => priority(a).compareTo(priority(b)));

      for (final iface in candidates) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && !addr.isLinkLocal) {
            return addr.address;
          }
        }
      }
    } catch (_) {
      // Fall through to strategy 2.
    }

    return null;
  }

  /// Resolves the local IP, falling back to `localhost`.
  static Future<String> getLocalIpAddressOrDefault() async {
    final ip = await getLocalIpAddress();
    return ip ?? '127.0.0.1';
  }
}
