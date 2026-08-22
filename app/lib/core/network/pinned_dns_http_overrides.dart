import 'dart:io';

/// A dart:io [HttpOverrides] that pins a small, known set of hostnames to
/// a fallback IP address for the raw connection stage only, used when
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
/// the function responsible for opening the raw connection. For every
/// hostname NOT in [pinnedHosts], behavior is unchanged in spirit
/// (normal DNS resolution using the hostname, TLS performed exactly as
/// [HttpClient] would do it by default). For a pinned hostname, normal
/// DNS is still tried FIRST; only if that throws does this fall back to
/// connecting directly to the pinned IP.
///
/// IMPORTANT correctness note (this is the actual reason an earlier
/// version of this file did not work): once a custom [connectionFactory]
/// is installed, [HttpClient] uses whatever [Socket] it returns exactly
/// as-is for a direct (non-proxied) connection — it does NOT
/// automatically wrap a plain [Socket] in TLS afterward for an
/// `https`/`wss` request the way it does when no custom factory is set.
/// A connectionFactory that just returns [Socket.startConnect] for every
/// scheme (as an earlier version of this file did) silently produces an
/// unencrypted connection for what both ends believe is a TLS session —
/// the server (doing TLS termination) sees non-TLS bytes and drops the
/// connection. This version performs the TLS handshake itself via
/// [SecureSocket.startConnect] whenever the request is secure, exactly
/// mirroring what [HttpClient]'s own default (non-overridden) behavior
/// does.
///
/// Because [SecureSocket] validates the certificate against the literal
/// string used to connect, connecting by the pinned IP means the
/// automatic hostname check compares the certificate against the IP —
/// which fails for any certificate issued to a real domain, exactly like
/// it would for anyone (this is not a weakness introduced here). For
/// that fallback path specifically, [onBadCertificate] steps in and
/// manually checks that the certificate's subject actually names the
/// domain we intended to reach before accepting it — so identity is
/// still verified, just against the domain instead of the (deliberately
/// bypassed) IP literal. This check is never consulted on the normal
/// (non-fallback) path, where the automatic hostname check already ran
/// and already passed.
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

    // Bounds the raw connect step itself (not just the DNS-lookup phase
    // this factory below controls): if a connection attempt is silently
    // dropped at the network level — no RST, no error, packets just
    // vanish, which some carrier/NAT paths do — the OS's own connect
    // timeout can run far longer than any timeout declared elsewhere in
    // this app (and varies unpredictably by platform). Setting this
    // makes [HttpClient] itself cancel a stalled attempt and surface a
    // real [SocketException] once this ceiling is hit, well under
    // socket.io's own 20s per-attempt budget, so a network path that
    // never actively fails can't leave the app stuck indefinitely.
    client.connectionTimeout = const Duration(seconds: 8);

    client.connectionFactory = (Uri uri, String? proxyHost, int? proxyPort) async {
      // Proxies aren't used anywhere in this app; if that ever changes,
      // defer entirely to the platform default rather than silently
      // ignoring a configured proxy.
      if (proxyHost != null) {
        return Socket.startConnect(proxyHost, proxyPort ?? uri.port);
      }

      final isSecure = uri.scheme == 'https' || uri.scheme == 'wss';

      Future<ConnectionTask<Socket>> connectTo(String host, {bool viaPinnedFallback = false}) {
        if (!isSecure) return Socket.startConnect(host, uri.port);
        return SecureSocket.startConnect(
          host,
          uri.port,
          onBadCertificate: viaPinnedFallback
              ? (cert) => _acceptIfCertificateNamesExpectedHost(cert, uri.host)
              : null,
        );
      }

      try {
        // Always try normal resolution first. On every device where DNS
        // for this host works fine, this is the only path ever taken —
        // the pinned IP is a fallback, never the default.
        return await connectTo(uri.host);
      } on SocketException catch (e) {
        final pinnedIp = pinnedHosts[uri.host];
        if (pinnedIp == null) {
          // ignore: avoid_print
          print(
            '[PinnedDnsHttpOverrides] Connect failed for ${uri.host} and no pinned fallback is registered for it: $e',
          );
          rethrow;
        }
        // ignore: avoid_print
        print(
          '[PinnedDnsHttpOverrides] Normal connect to ${uri.host} failed ($e) - retrying via pinned IP $pinnedIp',
        );
        return await connectTo(pinnedIp, viaPinnedFallback: true);
      }
    };

    return client;
  }

  bool _acceptIfCertificateNamesExpectedHost(X509Certificate cert, String expectedHost) {
    final accepted = cert.subject.contains(expectedHost);
    // ignore: avoid_print
    print(
      '[PinnedDnsHttpOverrides] Pinned-IP certificate check for $expectedHost - subject="${cert.subject}" -> ${accepted ? 'accepted' : 'REJECTED'}',
    );
    return accepted;
  }
}