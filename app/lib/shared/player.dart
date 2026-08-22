/// The two sides in a Cyber Tavla (backgammon) match.
///
/// [white] is visually themed as neon cyan and moves from point 24 down to
/// point 1 (bearing off past point 1). [black] is visually themed as neon
/// magenta and moves from point 1 up to point 24 (bearing off past point 24).
enum PlayerColor {
  white,
  black;

  /// The opposing color.
  PlayerColor get opponent =>
      this == PlayerColor.white ? PlayerColor.black : PlayerColor.white;

  /// Board traversal direction for this player: -1 for white, +1 for black.
  int get direction => this == PlayerColor.white ? -1 : 1;

  /// Wire-format identifier used when serializing to JSON for the
  /// realtime server / socket protocol.
  String get wireValue => this == PlayerColor.white ? 'white' : 'black';

  static PlayerColor fromWire(String value) {
    switch (value) {
      case 'white':
        return PlayerColor.white;
      case 'black':
        return PlayerColor.black;
      default:
        throw ArgumentError.value(value, 'value', 'Unknown PlayerColor wire value');
    }
  }
}