/// What happened to a subscription whose address the user typed in again.
enum SubscriptionUrlChange {
  /// The card now fetches from the new address.
  changed,

  /// The new address is the old one (same identity — a fragment or the order
  /// of the query does not make it another subscription). Nothing written.
  unchanged,

  /// Another card already has that address; the outcome carries that card.
  /// Two cards with one identity is exactly what ADR-0008 rules out: the
  /// servers would move from one to the other on the next refresh.
  taken,
}
