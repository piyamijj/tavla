import 'dart:io';

/// A dart:io [HttpOverrides] that pins a small, known set of hostnames to
/// a fallback IP address for the raw TCP connection stage only, used when
/// normal OS-level DNS resolution fails for that hostname.
///
/// Why this exists: some devices simply cannot resolve certain hostnames
/// at all — a "Private DNS" setting, an ad-block/VPN app, or a
/// carrier/device-level DNS filter can silently blocklist a domain before
/// any network request is even attempted. Dynamic-DNS domains such as
/// `*.duckdns.org` are a common target for exactly this kind of filtering
/// because of their history of malware C2 abuse. When that happens, the
/// failure surfaces as a `SocketException: Failed host lookup: '<host>'`
/// (OS error 7 / "No address associated with hostname") — a pure DNS
/// failure that happens before any TLS handshake, certificate check, or
/// server-side logic is ever reached, so nothing server-side can fix it.
///
/// How it works: this only overrides [HttpClient.connectionFactory] —
/// the function responsible for opening the raw TCP socket. For every
/// hostname NOT in [pinnedHosts], behavior is completely unchanged
/// (normal DNS resolution via [Socket.startConnect] using the hostname).
/// For a pinned hostname, normal DNS is still tried FIRST; only if that
/// throws does this fall back to connecting directly to the pinned IP.
/// Crucially, only the raw socket's destination address changes — the
/// request's [Uri] (and therefore the HTTP `Host` header, and for HTTPS
/// the TLS SNI extension and the hostname [HttpClient] verifies the
/// server's certificate against) is completely untouched, since that is
/// handled by [HttpClient] on top of whatever [Socket] this factory
/// returns. This means certificate validation stays fully correct and is
/// not weakened in any way: a certificate that wouldn't otherwise verify
/// still won't verify, this purely bypasses a broken/filtered DNS step.
///
/// Scope note: this affects every [HttpClient] created while this
/// override is installed (via [HttpOverrides.global]), which in this app
/// includes both the Socket.io polling transport and (transitively,
/// since [WebSocket.connect] is itself built on [HttpClient] internally)
/// its WebSocket upgrade — but nothing outside networking, and nothing
/// for hostnames that aren't explicitly pinned.
class PinnedDnsHttpOverrides extends HttpOverrides {
  /// Hostname -> fallback IP address literal (e.g.
  /// `{'cytavla.duckdns.org': '13.53.56.176'}`). Keep this list small and
  /// intentional — it exists purely as a last-resort escape hatch for a
  /// specific known host whose normal DNS entry point has been observed
  /// to fail on some devices, not a general-purpose DNS cache.
  final Map<String, String> pinnedHosts;

  PinnedDnsHttpOverrides(this.pinnedHosts);

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);

    // Bounds the raw TCP connect step itself (not just the DNS-lookup
    // phase this factory below controls): if a connection attempt is
    // silently dropped at the network level — no RST, no error, packets
    // just vanish, which some carrier/NAT paths do — the OS's own TCP
    // connect timeout can run far longer than any timeout declared
    // elsewhere in this app (and varies unpredictably by platform).
    // Setting this makes [HttpClient] itself cancel a stalled attempt and
    // surface a real [SocketException] once this ceiling is hit, well
    // under socket.io's own 20s per-attempt budget, so a network path
    // that never actively fails can't leave the app stuck indefinitely.
    client.connectionTimeout = const Duration(seconds: 8);

    client.connectionFactory = (Uri uri, String? proxyHost, int? proxyPort) async {
      // Proxies aren't used anywhere in this app; if that ever changes,
      // defer entirely to the platform default rather than silently
      // ignoring a configured proxy.
      if (proxyHost != null) {
        return Socket.startConnect(proxyHost, proxyPort ?? uri.port);
      }

      try {
        // Always try normal resolution first. On every device where DNS
        // for this host works fine, this is the only path ever taken —
        // the pinned IP is a fallback, never the default.
        return await Socket.startConnect(uri.host, uri.port);
      } on SocketException {
        final pinnedIp = pinnedHosts[uri.host];
        if (pinnedIp == null) rethrow;
        return await Socket.startConnect(pinnedIp, uri.port);
      }
    };

    return client;
  }
}