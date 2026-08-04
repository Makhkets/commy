/// A deliberately small YAML reader, just big enough for Clash subscriptions.
///
/// Pulling in a full YAML implementation would mean adding a dependency to
/// `commy_config`, and per CLAUDE.md §7.2 that is a decision for a human, not
/// for whoever happens to be writing the parser. Clash documents are also a
/// tiny, extremely regular corner of YAML, so the trade is a good one.
///
/// Supported: block mappings, block sequences, flow mappings and sequences,
/// single and double quoted scalars, `#` comments, booleans, integers and
/// nulls, and the `- key: value` form where the first entry of a mapping sits
/// on the dash line.
///
/// **Not** supported, on purpose: anchors and aliases (`&a`, `*a`), merge
/// keys (`<<`), multi-line scalars (`|`, `>`), multiple documents, tags and
/// explicit keys (`? `). A document using any of them returns `null` rather
/// than a half-read map, so the caller can fall back to another format
/// instead of importing something that is quietly wrong.
abstract final class ClashYamlReader {
  /// Constructs that put a document outside the supported subset.
  static final RegExp unsupported = RegExp(
    r'(^|\s)(&[A-Za-z0-9_\-]+|\*[A-Za-z0-9_\-]+|<<\s*:|[|>][+\-]?\s*$)',
    multiLine: true,
  );

  /// Parses [source] into a map, or returns `null`.
  ///
  /// Returns `null` when the document is empty, uses something outside the
  /// supported subset, or does not have a mapping at the top level.
  static Map<String, Object?>? tryParseDocument(String source) {
    if (source.trim().isEmpty || unsupported.hasMatch(source)) {
      return null;
    }
    final lines = _prepare(source);
    if (lines.isEmpty) {
      return null;
    }
    final value = _Parser(lines).parseNode(lines.first.indent);
    return value is Map<String, Object?> ? value : null;
  }

  /// Whether [source] smells like a Clash document.
  ///
  /// Cheap enough to run before the real parse, which matters because the
  /// format detection chain runs it on every subscription body.
  static bool looksLikeClash(String source) =>
      RegExp(r'^\s*proxies\s*:', multiLine: true).hasMatch(source);

  static List<_Line> _prepare(String source) {
    final result = <_Line>[];
    for (final raw in source.split(RegExp(r'\r?\n'))) {
      final expanded = raw.replaceAll('\t', '  ');
      final trimmed = expanded.trimLeft();
      if (trimmed.isEmpty) {
        continue;
      }
      final withoutComment = stripComment(trimmed);
      if (withoutComment.isEmpty) {
        continue;
      }
      if (withoutComment == '---' || withoutComment == '...') {
        continue;
      }
      result.add(
        _Line(expanded.length - trimmed.length, withoutComment.trimRight()),
      );
    }
    return result;
  }

  /// Removes a trailing `# comment` that is not inside quotes.
  static String stripComment(String text) {
    var quote = '';
    for (var index = 0; index < text.length; index++) {
      final char = text[index];
      if (quote.isNotEmpty) {
        if (char == quote) {
          quote = '';
        }
        continue;
      }
      if (char == '"' || char == "'") {
        quote = char;
        continue;
      }
      if (char == '#') {
        final previous = index == 0 ? ' ' : text[index - 1];
        if (previous == ' ' || previous == '\t') {
          return text.substring(0, index).trimRight();
        }
      }
    }
    return text;
  }

  /// Index of the `:` that separates a key from its value, or `-1`.
  static int findKeySeparator(String text) {
    var quote = '';
    for (var index = 0; index < text.length; index++) {
      final char = text[index];
      if (quote.isNotEmpty) {
        if (char == quote) {
          quote = '';
        }
        continue;
      }
      if (char == '"' || char == "'") {
        quote = char;
        continue;
      }
      if (char == '{' || char == '[') {
        return -1;
      }
      if (char == ':' && (index == text.length - 1 || text[index + 1] == ' ')) {
        return index;
      }
    }
    return -1;
  }

  /// Whether [text] begins a sequence item.
  static bool isSequenceItem(String text) =>
      text == '-' || text.startsWith('- ');

  /// Turns a scalar token into a `bool`, `int`, `double`, `String` or `null`.
  static Object? parseScalar(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      return null;
    }
    if (text.length >= 2 && text.startsWith('"') && text.endsWith('"')) {
      return unescape(text.substring(1, text.length - 1));
    }
    if (text.length >= 2 && text.startsWith("'") && text.endsWith("'")) {
      return text.substring(1, text.length - 1).replaceAll("''", "'");
    }
    final lower = text.toLowerCase();
    if (lower == 'true' || lower == 'yes' || lower == 'on') {
      return true;
    }
    if (lower == 'false' || lower == 'no' || lower == 'off') {
      return false;
    }
    if (lower == 'null' || lower == '~') {
      return null;
    }
    // A leading zero is meaningful in a Reality short id, so `01ab` and `007`
    // stay text rather than silently becoming numbers.
    if (!(text.length > 1 && text.startsWith('0'))) {
      final asInt = int.tryParse(text);
      if (asInt != null) {
        return asInt;
      }
      final asDouble = double.tryParse(text);
      if (asDouble != null) {
        return asDouble;
      }
    }
    return text;
  }

  /// Resolves the escapes a double quoted YAML scalar may hold.
  static String unescape(String text) {
    final buffer = StringBuffer();
    for (var index = 0; index < text.length; index++) {
      final char = text[index];
      if (char != r'\' || index == text.length - 1) {
        buffer.write(char);
        continue;
      }
      final next = text[index + 1];
      index++;
      if (next == 'n') {
        buffer.write('\n');
      } else if (next == 't') {
        buffer.write('\t');
      } else if (next == 'r') {
        buffer.write('\r');
      } else if (next == 'u' && index + 4 < text.length) {
        final code = int.tryParse(
          text.substring(index + 1, index + 5),
          radix: 16,
        );
        if (code == null) {
          buffer.write(next);
        } else {
          buffer.writeCharCode(code);
          index += 4;
        }
      } else {
        buffer.write(next);
      }
    }
    return buffer.toString();
  }

  /// Parses a flow mapping or sequence such as `{a: 1, b: [2, 3]}`.
  static Object? parseFlow(String source) => _FlowCursor(source).parseValue();
}

/// One prepared source line: how deep it sits and what is on it.
class _Line {
  const _Line(this.indent, this.text);

  final int indent;
  final String text;
}

class _Parser {
  _Parser(this.lines);

  final List<_Line> lines;
  int index = 0;

  Object? parseNode(int indent) {
    if (index >= lines.length) {
      return null;
    }
    final line = lines[index];
    if (line.indent < indent) {
      return null;
    }
    if (ClashYamlReader.isSequenceItem(line.text)) {
      return parseSequence(line.indent);
    }
    return parseMapping(line.indent);
  }

  List<Object?> parseSequence(int indent) {
    final items = <Object?>[];
    while (index < lines.length) {
      final line = lines[index];
      if (line.indent != indent || !ClashYamlReader.isSequenceItem(line.text)) {
        break;
      }
      final before = index;
      if (line.text.trim() == '-') {
        index++;
        if (index < lines.length && lines[index].indent > indent) {
          items.add(parseNode(lines[index].indent));
        } else {
          items.add(null);
        }
      } else {
        final content = line.text.substring(1).trimLeft();
        final column = line.indent + line.text.length - content.length;
        if (content.startsWith('{') || content.startsWith('[')) {
          items.add(ClashYamlReader.parseFlow(content));
          index++;
        } else if (ClashYamlReader.findKeySeparator(content) >= 0) {
          lines[index] = _Line(column, content);
          items.add(parseMapping(column));
        } else {
          items.add(ClashYamlReader.parseScalar(content));
          index++;
        }
      }
      if (index == before) {
        index++;
      }
    }
    return items;
  }

  Map<String, Object?> parseMapping(int indent) {
    final map = <String, Object?>{};
    while (index < lines.length) {
      final line = lines[index];
      if (line.indent != indent || ClashYamlReader.isSequenceItem(line.text)) {
        break;
      }
      final separator = ClashYamlReader.findKeySeparator(line.text);
      if (separator < 0) {
        break;
      }
      final key = _key(line.text.substring(0, separator));
      final rest = line.text.substring(separator + 1).trim();
      index++;
      if (rest.isNotEmpty) {
        map[key] = rest.startsWith('{') || rest.startsWith('[')
            ? ClashYamlReader.parseFlow(rest)
            : ClashYamlReader.parseScalar(rest);
        continue;
      }
      if (index >= lines.length) {
        map[key] = null;
        continue;
      }
      final next = lines[index];
      if (next.indent > indent) {
        map[key] = parseNode(next.indent);
      } else if (next.indent == indent &&
          ClashYamlReader.isSequenceItem(next.text)) {
        map[key] = parseSequence(indent);
      } else {
        map[key] = null;
      }
    }
    return map;
  }

  static String _key(String raw) {
    final trimmed = raw.trim();
    final scalar = ClashYamlReader.parseScalar(trimmed);
    return scalar == null ? trimmed : '$scalar';
  }
}

class _FlowCursor {
  _FlowCursor(this.source);

  final String source;
  int index = 0;

  Object? parseValue() {
    skipSpaces();
    if (index >= source.length) {
      return null;
    }
    final char = source[index];
    if (char == '{') {
      return parseMapping();
    }
    if (char == '[') {
      return parseSequence();
    }
    if (char == '"' || char == "'") {
      return ClashYamlReader.parseScalar(parseQuoted(char));
    }
    return ClashYamlReader.parseScalar(parseBare());
  }

  Map<String, Object?> parseMapping() {
    final map = <String, Object?>{};
    index++;
    while (index < source.length) {
      skipSpaces();
      if (index >= source.length || source[index] == '}') {
        index++;
        break;
      }
      final key = parseKey();
      skipSpaces();
      if (index < source.length && source[index] == ':') {
        index++;
      }
      map[key] = parseValue();
      skipSpaces();
      if (index < source.length && source[index] == ',') {
        index++;
        continue;
      }
      if (index < source.length && source[index] == '}') {
        index++;
      }
      break;
    }
    return map;
  }

  List<Object?> parseSequence() {
    final items = <Object?>[];
    index++;
    while (index < source.length) {
      skipSpaces();
      if (index >= source.length || source[index] == ']') {
        index++;
        break;
      }
      items.add(parseValue());
      skipSpaces();
      if (index < source.length && source[index] == ',') {
        index++;
        continue;
      }
      if (index < source.length && source[index] == ']') {
        index++;
      }
      break;
    }
    return items;
  }

  String parseKey() {
    skipSpaces();
    if (index < source.length &&
        (source[index] == '"' || source[index] == "'")) {
      return parseQuoted(source[index]).replaceAll('"', '').replaceAll("'", '');
    }
    final start = index;
    while (index < source.length &&
        source[index] != ':' &&
        source[index] != ',' &&
        source[index] != '}') {
      index++;
    }
    return source.substring(start, index).trim();
  }

  String parseQuoted(String quote) {
    final start = index;
    index++;
    while (index < source.length && source[index] != quote) {
      if (source[index] == r'\') {
        index++;
      }
      index++;
    }
    if (index < source.length) {
      index++;
    }
    return source.substring(start, index);
  }

  String parseBare() {
    final start = index;
    while (index < source.length &&
        source[index] != ',' &&
        source[index] != '}' &&
        source[index] != ']') {
      index++;
    }
    return source.substring(start, index);
  }

  void skipSpaces() {
    while (index < source.length &&
        (source[index] == ' ' || source[index] == '\t')) {
      index++;
    }
  }
}
