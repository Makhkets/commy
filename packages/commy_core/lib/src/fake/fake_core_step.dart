/// A call on `CoreClient` that `FakeCoreClient` can be told to fail.
///
/// Named after the method rather than after the failure, because a test reads
/// as "make `start` fail with `permissionDenied`" — the failure is chosen at
/// the call site and is not fixed per step.
enum FakeCoreStep {
  /// `start`. Failing here also drives the tunnel into `error`, the way the
  /// native side does when the user declines the system VPN prompt.
  start,

  /// `stop`.
  stop,

  /// `reload`. Fails like [start], including the state change.
  reload,

  /// `select`.
  select,

  /// `urlTest`. Note that a *timeout* is not a failure — that is `null`, set
  /// through `FakeCoreClient.setLatency`.
  urlTest,

  /// `proxies`.
  proxies,
}
