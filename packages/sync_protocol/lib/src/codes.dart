import 'dart:math';

/// Pairing codes: 6 characters from an unambiguous alphabet (no 0/O/1/I/L),
/// displayed as XXX-XXX.
class PairCodes {
  const PairCodes._();

  static const String alphabet = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';

  static String generate(Random rng) {
    final chars = List.generate(
      6,
      (_) => alphabet[rng.nextInt(alphabet.length)],
    ).join();
    return chars;
  }

  /// Canonical form: uppercase, no separators. Returns null if invalid.
  static String? normalize(String input) {
    final cleaned = input.toUpperCase().replaceAll(RegExp(r'[\s\-]'), '');
    if (cleaned.length != 6) return null;
    for (final c in cleaned.split('')) {
      if (!alphabet.contains(c)) return null;
    }
    return cleaned;
  }

  /// Display form: ABC-123.
  static String pretty(String code) =>
      code.length == 6 ? '${code.substring(0, 3)}-${code.substring(3)}' : code;
}
