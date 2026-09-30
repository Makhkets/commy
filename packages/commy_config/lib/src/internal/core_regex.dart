/// Whether a regular expression is one the core can compile.
///
/// The core compiles `domain_regex` with Go's `regexp`, which reads RE2
/// syntax, and one expression that does not compile fails the whole document
/// (`route/rule/rule_item_domain_regex.go`): no server connects until the rule
/// is found and deleted. Dart's [RegExp] reads ECMAScript instead. The two
/// agree on most of what a pattern for a name looks like, but not on all of
/// it. Dart takes a lookahead, a backreference, `\q` for `q`, `[]` for a
/// class of nothing and `a{2000}`, and Go refuses every one of them; Go takes
/// `(?i)`, `(?P<name>…)` and `\Q…\E`, and Dart refuses those.
///
/// So a pattern is read here the way Go's parser (`regexp/syntax/parse.go`)
/// reads it wherever the two languages differ — escapes, classes, group
/// openings, repeat counts — and written out as ECMAScript that compiles
/// exactly when the original does. [RegExp] then checks what they share:
/// balanced groups, something in front of every quantifier, ranges in order.
/// What either side refuses is refused.
///
/// One refusal is deliberately wider than Go's: a Unicode class (`\pL`,
/// `\p{Greek}`). Telling Go's valid names from the rest would take its
/// tables, such a class has no place in a pattern for a host name, and a
/// refused rule costs that rule rather than the tunnel.
abstract final class CoreRegex {
  /// Whether Go's `regexp.Compile` accepts [pattern].
  static bool accepts(String pattern) {
    final translated = _Translation(pattern).run();
    if (translated == null) {
      return false;
    }
    try {
      RegExp(translated);
      return true;
    } on FormatException {
      return false;
    }
  }
}

/// One pass over a pattern, from Go's syntax into ECMAScript's.
///
/// Each step consumes what it recognised and returns `false` (or `null`) for
/// what Go would refuse.
class _Translation {
  _Translation(String pattern) : _runes = pattern.runes.toList(growable: false);

  /// The most copies of one thing Go lets `{n,m}` make, nesting included:
  /// `a{1001}` is refused, and so is `(a{40}){30}`.
  static const int _maxCopies = 1000;

  /// What a zero-width assertion is written as.
  ///
  /// An empty group: Go lets a quantifier follow `^` or `\b`, ECMAScript
  /// does not, and an empty group is an atom both take.
  static const String _assertion = '(?:)';

  static const Set<String> _posixClasses = <String>{
    'alnum',
    'alpha',
    'ascii',
    'blank',
    'cntrl',
    'digit',
    'graph',
    'lower',
    'print',
    'punct',
    'space',
    'upper',
    'word',
    'xdigit',
  };

  static final RegExp _captureName = RegExp(r'^[A-Za-z0-9_]+$');

  static const int _backslash = 0x5C;
  static const int _openParen = 0x28;
  static const int _closeParen = 0x29;
  static const int _openBracket = 0x5B;
  static const int _closeBracket = 0x5D;
  static const int _openBrace = 0x7B;
  static const int _closeBrace = 0x7D;
  static const int _star = 0x2A;
  static const int _plus = 0x2B;
  static const int _question = 0x3F;
  static const int _colon = 0x3A;
  static const int _comma = 0x2C;
  static const int _minus = 0x2D;
  static const int _caret = 0x5E;
  static const int _dollar = 0x24;
  static const int _less = 0x3C;
  static const int _greater = 0x3E;
  static const int _zero = 0x30;
  static const int _one = 0x31;
  static const int _seven = 0x37;
  static const int _nine = 0x39;
  static const int _upperE = 0x45;
  static const int _upperP = 0x50;
  static const int _lowerP = 0x70;
  static const int _lowerX = 0x78;

  /// Go's flags inside `(?…)`: `i`, `m`, `s` and `U`.
  static const Set<int> _flags = <int>{0x69, 0x6D, 0x73, 0x55};

  /// Go's Perl classes, `\d \D \s \S \w \W`. ECMAScript has the same six.
  static const Set<int> _perlClasses = <int>{
    0x64,
    0x44,
    0x73,
    0x53,
    0x77,
    0x57,
  };

  /// `\A \z \b \B`, which match a place rather than a character.
  static const Set<int> _assertions = <int>{0x41, 0x7A, 0x62, 0x42};

  /// The C escapes Go knows, and the character each one stands for.
  static const Map<int, int> _cEscapes = <int, int>{
    0x61: 0x07, // \a
    0x66: 0x0C, // \f
    0x6E: 0x0A, // \n
    0x72: 0x0D, // \r
    0x74: 0x09, // \t
    0x76: 0x0B, // \v
  };

  final List<int> _runes;
  final StringBuffer _out = StringBuffer();
  int _at = 0;

  /// For each group still open, the outermost first, the most copies any
  /// `{n,m}` inside it makes of one thing.
  final List<int> _copies = <int>[1];

  /// The same for the atom just written, until it is known whether a
  /// `{n,m}` applies to it.
  int _pending = 1;

  bool get _done => _at >= _runes.length;

  int? _peek([int ahead = 0]) {
    final index = _at + ahead;
    return index < _runes.length ? _runes[index] : null;
  }

  /// The pattern in ECMAScript, or `null` when Go would not compile it.
  String? run() {
    while (!_done) {
      final rune = _runes[_at];
      final ok = switch (rune) {
        _openParen => _group(),
        _closeParen => _close(),
        _openBrace => _repeat(),
        _star || _plus || _question => _copy(),
        _ => _atom(rune),
      };
      if (!ok) {
        return null;
      }
    }
    return _out.toString();
  }

  /// Anything that is matched rather than repeated.
  bool _atom(int rune) {
    _settle();
    return switch (rune) {
      _openBracket => _class(),
      _backslash => _escape(),
      _caret || _dollar => _zeroWidth(),
      _ => _copy(),
    };
  }

  /// The atom before this point takes no more quantifiers: what it counts
  /// now counts for the group around it.
  void _settle() {
    if (_pending > _copies.last) {
      _copies.last = _pending;
    }
    _pending = 1;
  }

  bool _copy() {
    _out.writeCharCode(_runes[_at++]);
    return true;
  }

  bool _zeroWidth() {
    _at++;
    _out.write(_assertion);
    return true;
  }

  bool _close() {
    _settle();
    if (_copies.length == 1) {
      return false;
    }
    _pending = _copies.removeLast();
    return _copy();
  }

  /// `(`, and Go's `(?…)` forms (`parsePerlFlags`).
  bool _group() {
    if (_peek(1) != _question) {
      return _open('(', 1);
    }
    final nameStart = _peek(2) == _less
        ? 3
        : _peek(2) == _upperP && _peek(3) == _less
            ? 4
            : 0;
    if (nameStart > 0) {
      var end = _at + nameStart;
      while (end < _runes.length && _runes[end] != _greater) {
        end++;
      }
      if (end >= _runes.length) {
        return false;
      }
      final name = String.fromCharCodes(_runes, _at + nameStart, end);
      // A lookbehind, `(?<=` or `(?<!`, ends up here too.
      if (!_captureName.hasMatch(name)) {
        return false;
      }
      // Go takes a name that starts with a digit, and the same name twice;
      // ECMAScript takes neither. The name changes nothing about whether the
      // pattern compiles, so the group is written without one.
      return _open('(', end + 1 - _at);
    }
    var at = _at + 2;
    var negated = false;
    var sawFlag = false;
    while (at < _runes.length) {
      final rune = _runes[at++];
      if (_flags.contains(rune)) {
        sawFlag = true;
      } else if (rune == _minus && !negated) {
        negated = true;
        sawFlag = false;
      } else if (rune == _colon || rune == _closeParen) {
        if (negated && !sawFlag) {
          return false;
        }
        // Flags change what matches, not whether it compiles, and
        // ECMAScript has no inline ones: the group stays, the flags go. A
        // flag setting on its own is no atom at all, and a quantifier after
        // it still belongs to whatever came before.
        if (rune == _closeParen) {
          _at = at;
          return true;
        }
        return _open('(?:', at - _at);
      } else {
        // A lookahead, `(?=` or `(?!`, among others.
        return false;
      }
    }
    return false;
  }

  bool _open(String written, int length) {
    _settle();
    _copies.add(1);
    _out.write(written);
    _at += length;
    return true;
  }

  /// A backslash outside a class.
  bool _escape() {
    final letter = _peek(1);
    if (letter == null) {
      return false;
    }
    if (_assertions.contains(letter)) {
      _at += 2;
      _out.write(_assertion);
      return true;
    }
    if (letter == 0x51) {
      // \Q…\E: everything up to \E, or to the end, is itself.
      _at += 2;
      while (!_done && !(_peek() == _backslash && _peek(1) == _upperE)) {
        _out.write(_literal(_runes[_at++]));
      }
      if (!_done) {
        _at += 2;
      }
      return true;
    }
    // \C, and the Unicode classes.
    if (letter == 0x43 || letter == _lowerP || letter == _upperP) {
      return false;
    }
    if (_perlClass()) {
      return true;
    }
    final rune = _escapedRune();
    if (rune == null) {
      return false;
    }
    _out.write(_literal(rune));
    return true;
  }

  /// `\d \D \s \S \w \W`, which both languages read alike.
  bool _perlClass() {
    final letter = _peek(1);
    if (_peek() != _backslash || !_perlClasses.contains(letter)) {
      return false;
    }
    _out
      ..writeCharCode(_backslash)
      ..writeCharCode(letter!);
    _at += 2;
    return true;
  }

  /// Go's `parseEscape`: the one character an escape stands for.
  int? _escapedRune() {
    _at++;
    if (_done) {
      return null;
    }
    final rune = _runes[_at++];
    if (rune < 0x80 && !_isAlphanumeric(rune)) {
      return rune;
    }
    if (rune >= _one && rune <= _seven) {
      // A single digit is a backreference, which Go does not have.
      return _isOctal(_peek()) ? _octal(rune) : null;
    }
    if (rune == _zero) {
      return _octal(rune);
    }
    if (rune == _lowerX) {
      return _hex();
    }
    return _cEscapes[rune];
  }

  int _octal(int first) {
    var value = first - _zero;
    for (var digits = 1; digits < 3 && _isOctal(_peek()); digits++) {
      value = value * 8 + _runes[_at++] - _zero;
    }
    return value;
  }

  int? _hex() {
    if (_done) {
      return null;
    }
    final first = _runes[_at++];
    if (first == _openBrace) {
      var value = 0;
      var digits = 0;
      while (true) {
        if (_done) {
          return null;
        }
        final rune = _runes[_at++];
        if (rune == _closeBrace) {
          break;
        }
        final digit = _hexValue(rune);
        if (digit < 0) {
          return null;
        }
        value = value * 16 + digit;
        if (value > 0x10FFFF) {
          return null;
        }
        digits++;
      }
      return digits == 0 ? null : value;
    }
    if (_done) {
      return null;
    }
    final high = _hexValue(first);
    final low = _hexValue(_runes[_at++]);
    return high < 0 || low < 0 ? null : high * 16 + low;
  }

  /// A bracketed class, as Go's `parseClass` reads it.
  ///
  /// A `]` straight after `[` or `[^` is a member, not the end: `[]a]` is a
  /// class of two, and `[]` has no end at all. ECMAScript reads both
  /// differently, so every member is written out as an escape.
  bool _class() {
    _at++;
    _out.write('[');
    if (_peek() == _caret) {
      _at++;
      _out.write('^');
    }
    var first = true;
    while (true) {
      if (_done) {
        return false;
      }
      if (_peek() == _closeBracket && !first) {
        break;
      }
      first = false;
      final named = _posixClass();
      if (named == false) {
        return false;
      }
      if (named == true || _perlClass()) {
        continue;
      }
      if (_peek() == _backslash &&
          (_peek(1) == _lowerP || _peek(1) == _upperP)) {
        return false;
      }
      final low = _classRune();
      if (low == null) {
        return false;
      }
      final after = _peek(1);
      if (_peek() == _minus && after != null && after != _closeBracket) {
        _at++;
        final high = _classRune();
        // Checked here, on whole characters: past U+FFFF the escapes below
        // no longer tell which end is higher.
        if (high == null || high < low) {
          return false;
        }
        _out.write('${_literal(low)}-${_literal(high)}');
      } else {
        _out.write(_literal(low));
      }
    }
    _at++;
    _out.write(']');
    return true;
  }

  /// `[:alpha:]` and the rest: `true` when read, `false` when Go refuses the
  /// name, `null` when this is no such class.
  bool? _posixClass() {
    if (_peek() != _openBracket || _peek(1) != _colon) {
      return null;
    }
    var end = _at + 2;
    while (end + 1 < _runes.length &&
        !(_runes[end] == _colon && _runes[end + 1] == _closeBracket)) {
      end++;
    }
    if (end + 1 >= _runes.length) {
      return null;
    }
    var name = String.fromCharCodes(_runes, _at + 2, end);
    if (name.startsWith('^')) {
      name = name.substring(1);
    }
    if (!_posixClasses.contains(name)) {
      return false;
    }
    _at = end + 2;
    _out.write(r'\w');
    return true;
  }

  /// One member of a class, or one end of a range.
  int? _classRune() {
    if (_done) {
      return null;
    }
    return _peek() == _backslash ? _escapedRune() : _runes[_at++];
  }

  /// `{n}`, `{n,}` or `{n,m}` as Go's `parseRepeat` reads it.
  ///
  /// What does not read as one is a brace, in Go as in ECMAScript.
  bool _repeat() {
    final start = _at;
    var at = _at + 1;
    int? number() {
      final from = at;
      while (at < _runes.length && _runes[at] >= _zero && _runes[at] <= _nine) {
        at++;
      }
      // Go reads a leading zero as "not a count", and the brace as itself.
      if (at == from || (at - from > 1 && _runes[from] == _zero)) {
        return null;
      }
      // Past five digits the exact number no longer matters.
      return at - from > 5
          ? _maxCopies + 1
          : int.parse(String.fromCharCodes(_runes, from, at));
    }

    final min = number();
    var max = min;
    if (min != null && at < _runes.length && _runes[at] == _comma) {
      at++;
      max = at < _runes.length && _runes[at] == _closeBrace ? -1 : number();
    }
    if (min == null ||
        max == null ||
        at >= _runes.length ||
        _runes[at] != _closeBrace) {
      _settle();
      _at++;
      _out.write(_literal(_openBrace));
      return true;
    }
    if (min > _maxCopies || max > _maxCopies || (max >= 0 && min > max)) {
      return false;
    }
    // Go counts copies down every nesting: `(a{40}){30}` is 1200 of `a`.
    // Nothing inside a `{0}` counts, since there is none of it.
    final copies = max < 0 ? min : max;
    if (copies == 0) {
      _pending = 1;
    } else {
      _pending *= copies;
      if (_pending > _maxCopies) {
        return false;
      }
    }
    _out.write(String.fromCharCodes(_runes, start, at + 1));
    _at = at + 1;
    return true;
  }

  /// [rune] as an ECMAScript escape that means that one character.
  ///
  /// Outside the Basic Multilingual Plane it stands in as U+FFFF: ECMAScript
  /// without the `u` flag sees such a character as two, and a range between
  /// halves would be refused for a reason Go does not have.
  static String _literal(int rune) {
    final unit = rune > 0xFFFF ? 0xFFFF : rune;
    return '\\u${unit.toRadixString(16).padLeft(4, '0')}';
  }

  static bool _isAlphanumeric(int rune) =>
      (rune >= _zero && rune <= _nine) ||
      (rune >= 0x41 && rune <= 0x5A) ||
      (rune >= 0x61 && rune <= 0x7A);

  static bool _isOctal(int? rune) =>
      rune != null && rune >= _zero && rune <= _seven;

  static int _hexValue(int rune) {
    if (rune >= _zero && rune <= _nine) {
      return rune - _zero;
    }
    if (rune >= 0x61 && rune <= 0x66) {
      return rune - 0x61 + 10;
    }
    if (rune >= 0x41 && rune <= 0x46) {
      return rune - 0x41 + 10;
    }
    return -1;
  }
}
