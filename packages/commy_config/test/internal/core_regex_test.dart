import 'package:commy_config/src/internal/core_regex.dart';
import 'package:test/test.dart';

/// Each verdict below is what Go 1.24's `regexp.Compile` answered for the
/// pattern, checked by hand; so were some hundreds of thousands of random
/// patterns when [CoreRegex] was written, with no pattern accepted here that
/// Go refused.
void main() {
  group('CoreRegex', () {
    test('accepts what a rule for a name usually looks like', () {
      for (final pattern in <String>[
        r'^ads\.',
        r'(^|\.)example\.com$',
        r'^[a-z0-9-]+\.cdn\.example\.com$',
        r'.*\.example\.(com|net)$',
        r'\d+\.example\.com',
        r'^[^.]+\.example\.com$',
      ]) {
        expect(CoreRegex.accepts(pattern), isTrue, reason: pattern);
      }
    });

    test('refuses what Dart compiles and Go does not', () {
      for (final pattern in <String>[
        '(?=a)',
        '(?!a)',
        '(?<=a)b',
        '(?<!a)b',
        r'(a)\1',
        r'(?<x>a)\k<x>',
        r'\q',
        r'\Z',
        r'\cJ',
        r'\u0041',
        r'\xZZ',
        '[]',
        '[^]',
        r'[\b]',
        r'[a-\d]',
        '[[:foo:]]',
        'a{1001}',
        'a{99999}',
        '(a{40}){30}',
        '((a{10}){10}){11}',
        '(?i-)a',
        '(?#x)',
        '(?>a)',
      ]) {
        expect(CoreRegex.accepts(pattern), isFalse, reason: pattern);
      }
    });

    test('accepts what Go compiles and Dart does not', () {
      for (final pattern in <String>[
        '(?i)example',
        '(?i:a)b',
        '(?-i)a',
        '(?)',
        '(?P<name>a)',
        '(?<1a>b)',
        '(?P<a>x)|(?P<a>y)',
        r'\Qa.b\E',
        r'\Q(\E',
        r'\A',
        r'\z',
        '^*',
        r'\b+',
        '[]a]',
        '[[:alpha:]]',
        '[[:^digit:]]',
        r'\x{41}',
        '((a{100}){0}){20}',
      ]) {
        expect(CoreRegex.accepts(pattern), isTrue, reason: pattern);
      }
    });

    test('refuses what neither compiles', () {
      for (final pattern in <String>[
        '*.example.com',
        'a**',
        'a{2}{3}',
        'a{2,1}',
        '[z-a]',
        '[😂-😀]',
        '(',
        ')',
        '[a',
        r'\',
        r'\8',
      ]) {
        expect(CoreRegex.accepts(pattern), isFalse, reason: pattern);
      }
    });

    test('reads a brace that is no count as a brace, as Go does', () {
      for (final pattern in <String>['a{,5}', 'a{01}', 'a{1', '{', 'a}']) {
        expect(CoreRegex.accepts(pattern), isTrue, reason: pattern);
      }
    });

    test('refuses a Unicode class, though Go knows some', () {
      // Deliberately wider than Go: telling its valid names from the rest
      // would take its tables.
      for (final pattern in <String>[r'\pL', r'\p{Greek}', r'[\PL]']) {
        expect(CoreRegex.accepts(pattern), isFalse, reason: pattern);
      }
    });
  });
}
