import 'dart:io';

import 'package:path/path.dart' as p;

/// 仓库内编写的日志、错误、测试输出与工具输出必须为英文。
///
/// 注释与 `arb/` 本地化文案不在此检查范围内；测试里的中文 UI 夹具只允许
/// 出现在显式验证中文 locale 的断言中，因此扫描器只检查会进入测试输出的
/// 描述、失败消息与打印调用。
void main(List<String> arguments) {
  final root = Directory(arguments.isEmpty ? '.' : arguments.first);
  final violations = scanRepository(root);
  if (violations.isEmpty) {
    stdout.writeln('language check passed');
    return;
  }
  for (final violation in violations) {
    stderr.writeln(violation);
  }
  stderr.writeln('${violations.length} language violation(s) found');
  exitCode = 1;
}

class LanguageViolation {
  const LanguageViolation(this.path, this.line, this.rule, this.text);

  final String path;
  final int line;
  final String rule;
  final String text;

  @override
  String toString() => '$path:$line: $rule: $text';
}

final _cjk = RegExp(r'[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]');

bool containsCjk(String value) => _cjk.hasMatch(value);

Set<int> _allowedLines(String source) {
  final allowed = <int>{};
  final lines = source.split('\n');
  for (var index = 0; index < lines.length; index++) {
    if (!lines[index].contains('language-check: allow external-data')) continue;
    allowed.add(index + 1);
    if (index + 2 <= lines.length) allowed.add(index + 2);
  }
  return allowed;
}

List<LanguageViolation> scanRepository(Directory root) {
  final violations = <LanguageViolation>[];
  for (final file in _sourceFiles(root)) {
    final relative = p.relative(file.path, from: root.path);
    final text = file.readAsStringSync();
    final allowedLines = _allowedLines(text);
    if (relative.endsWith('.rs')) {
      violations.addAll(
        scanRust(
          relative,
          text,
        ).where((violation) => !allowedLines.contains(violation.line)),
      );
    } else if (relative.endsWith('.dart')) {
      violations.addAll(
        scanDart(
          relative,
          text,
        ).where((violation) => !allowedLines.contains(violation.line)),
      );
    } else if (relative.endsWith('.yml') || relative.endsWith('.yaml')) {
      violations.addAll(
        scanWorkflow(
          relative,
          text,
        ).where((violation) => !allowedLines.contains(violation.line)),
      );
    }
  }
  final unique = <String, LanguageViolation>{};
  for (final violation in violations) {
    unique.putIfAbsent(violation.toString(), () => violation);
  }
  return unique.values.toList();
}

Iterable<File> _sourceFiles(Directory root) sync* {
  final setup = File(p.join(root.path, 'setup.dart'));
  if (setup.existsSync()) yield setup;
  final roots = <String>[
    p.join(root.path, 'core'),
    p.join(root.path, 'plugins', 'flspeak_ffi', 'rust', 'src'),
    p.join(root.path, 'lib'),
    p.join(root.path, 'test'),
    p.join(root.path, 'integration_test'),
    p.join(root.path, 'tool'),
    p.join(root.path, '.github', 'workflows'),
  ];
  for (final path in roots) {
    final directory = Directory(path);
    if (!directory.existsSync()) continue;
    for (final entity in directory.listSync(recursive: true)) {
      if (entity is! File) continue;
      final relative = p.relative(entity.path, from: root.path);
      if (relative.startsWith(p.join('lib', 'l10n'))) continue;
      if (relative.endsWith('frb_generated.rs')) continue;
      if (relative == p.join('tool', 'check_language.dart')) continue;
      if (relative == p.join('tool', 'check_language_test.dart')) continue;
      final extension = p.extension(relative);
      if (extension == '.rs' ||
          extension == '.dart' ||
          extension == '.yml' ||
          extension == '.yaml') {
        yield entity;
      }
    }
  }
}

List<LanguageViolation> scanRust(String path, String source) {
  final violations = <LanguageViolation>[];
  final stripped = _stripComments(
    source,
    lineComment: '//',
    blockComment: true,
    singleQuoteStrings: false,
  );

  void add(int offset, String rule, String literal) {
    violations.add(
      LanguageViolation(
        path,
        _lineAt(source, offset),
        rule,
        literal.replaceAll('\n', r'\n'),
      ),
    );
  }

  for (final macro in _rustOutputMacros.allMatches(stripped)) {
    final open = _firstDelimiter(stripped, macro.end);
    if (open == null) continue;
    final close = _matchingDelimiter(stripped, open);
    if (close == null) continue;
    final body = stripped.substring(open + 1, close);
    for (final literal in _stringLiterals(body)) {
      if (containsCjk(literal.value)) {
        add(
          open + 1 + literal.start,
          '${macro.group(1)} message',
          literal.value,
        );
      }
    }
  }

  for (final attribute in _rustErrorAttribute.allMatches(stripped)) {
    final literal = attribute.group(1)!;
    if (containsCjk(literal)) {
      add(attribute.start, 'error Display', literal);
    }
  }

  for (final attribute in _rustIgnoreAttribute.allMatches(stripped)) {
    final literal = attribute.group(1)!;
    if (containsCjk(literal)) {
      add(attribute.start, 'ignore reason', literal);
    }
  }

  for (final call in _rustExpectCall.allMatches(stripped)) {
    final literal = call.group(2)!;
    if (containsCjk(literal)) {
      add(call.start, '${call.group(1)} message', literal);
    }
  }

  for (final literal in _stringLiterals(stripped)) {
    if (containsCjk(literal.value)) {
      add(literal.start, 'string literal', literal.value);
    }
  }

  return violations;
}

final _rustOutputMacros = RegExp(
  r'\b(log_(?:trace|debug|info|warn|error)|tracing::(?:trace|debug|info|warn|error)|println|eprintln|panic|unreachable|todo|debug_assert(?:_eq|_ne)?|assert(?:_eq|_ne)?)!\s*',
);

final _rustErrorAttribute = RegExp(r'#\[error\(\s*"((?:[^"\\]|\\.)*)"');

final _rustIgnoreAttribute = RegExp(r'#\[ignore\s*=\s*"((?:[^"\\]|\\.)*)"');

final _rustExpectCall = RegExp(
  r'\.(expect|expect_err)\(\s*"((?:[^"\\]|\\.)*)"',
);

List<LanguageViolation> scanDart(String path, String source) {
  final violations = <LanguageViolation>[];
  final stripped = _stripComments(
    source,
    lineComment: '//',
    blockComment: true,
    singleQuoteStrings: true,
  );

  void add(RegExpMatch match, String rule, String literal) {
    violations.add(
      LanguageViolation(
        path,
        _lineAt(source, match.start),
        rule,
        literal.replaceAll('\n', r'\n'),
      ),
    );
  }

  for (final match in _dartTestDescription.allMatches(stripped)) {
    final literal = match.group(2)!;
    if (containsCjk(literal)) add(match, 'test description', literal);
  }

  for (final match in _dartReason.allMatches(stripped)) {
    final literal = match.group(1)!;
    if (containsCjk(literal)) add(match, 'test reason', literal);
  }

  for (final match in _dartPrint.allMatches(stripped)) {
    final literal = match.group(2)!;
    if (containsCjk(literal)) add(match, '${match.group(1)} output', literal);
  }

  for (final match in _dartWrite.allMatches(stripped)) {
    final literal = match.group(2)!;
    if (containsCjk(literal)) add(match, '${match.group(1)} output', literal);
  }

  for (final match in _dartLog.allMatches(stripped)) {
    final literal = match.group(2)!;
    if (containsCjk(literal)) add(match, '${match.group(1)} message', literal);
  }

  for (final match in _dartFailure.allMatches(stripped)) {
    final literal = match.group(2)!;
    if (containsCjk(literal)) add(match, '${match.group(1)} message', literal);
  }

  for (final match in _dartThrow.allMatches(stripped)) {
    final literal = match.group(2)!;
    if (containsCjk(literal)) add(match, '${match.group(1)} message', literal);
  }

  for (final match in _dartAssert.allMatches(stripped)) {
    final literal = match.group(1)!;
    if (containsCjk(literal)) add(match, 'assert message', literal);
  }

  return violations;
}

final _dartTestDescription = RegExp(
  r"\b(test|testWidgets|group)\s*(?:<[^>]*>\s*)?\(\s*'((?:[^'\\]|\\.)*)'",
);

final _dartReason = RegExp(r"\breason\s*:\s*'((?:[^'\\]|\\.)*)'");

final _dartPrint = RegExp(r"\b(print|debugPrint)\s*\(\s*'((?:[^'\\]|\\.)*)'");

final _dartWrite = RegExp(
  r"\b(stdout|stderr)\.(?:write|writeln)\s*\(\s*'((?:[^'\\]|\\.)*)'",
);

final _dartLog = RegExp(
  r"\b(logDebug|logInfo|logWarn|logError)\s*\(\s*'((?:[^'\\]|\\.)*)'",
);

final _dartFailure = RegExp(r"\b(fail)\s*\(\s*'((?:[^'\\]|\\.)*)'");

final _dartThrow = RegExp(
  r"\b(StateError|ArgumentError|Exception|FormatException)\s*\(\s*'((?:[^'\\]|\\.)*)'",
);

final _dartAssert = RegExp(r"\bassert\s*\([^;]*?,\s*'((?:[^'\\]|\\.)*)'");

List<LanguageViolation> scanWorkflow(String path, String source) {
  final violations = <LanguageViolation>[];
  final lines = source.split('\n');
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('#')) continue;
    final echo = RegExp(r'''\becho\s+(?:["']?)(.*)''').firstMatch(line);
    if (echo != null && containsCjk(echo.group(1)!)) {
      violations.add(
        LanguageViolation(path, index + 1, 'workflow echo', line.trim()),
      );
    }
  }
  return violations;
}

int _lineAt(String source, int offset) =>
    source.substring(0, offset).split('\n').length;

int? _firstDelimiter(String source, int offset) {
  for (var index = offset; index < source.length; index++) {
    final char = source[index];
    if (char == '(' || char == '[' || char == '{') return index;
    if (char == ';' || char == '\n') return null;
  }
  return null;
}

int? _matchingDelimiter(String source, int open) {
  final pairs = {'(': ')', '[': ']', '{': '}'};
  final stack = <String>[];
  var index = open;
  while (index < source.length) {
    final char = source[index];
    if (char == '"') {
      index = _skipString(source, index) + 1;
      continue;
    }
    if (pairs.containsKey(char)) {
      stack.add(pairs[char]!);
    } else if (stack.isNotEmpty && char == stack.last) {
      stack.removeLast();
      if (stack.isEmpty) return index;
    }
    index++;
  }
  return null;
}

int _skipString(String source, int start) {
  var index = start + 1;
  while (index < source.length) {
    if (source[index] == r'\') {
      index += 2;
      continue;
    }
    if (source[index] == '"') return index;
    index++;
  }
  return source.length - 1;
}

class _Literal {
  const _Literal(this.start, this.value);

  final int start;
  final String value;
}

Iterable<_Literal> _stringLiterals(String source) sync* {
  var index = 0;
  while (index < source.length) {
    if (source[index] != '"') {
      index++;
      continue;
    }
    final start = index;
    index++;
    final buffer = StringBuffer();
    while (index < source.length) {
      final char = source[index];
      if (char == r'\') {
        if (index + 1 < source.length) buffer.write(source[index + 1]);
        index += 2;
        continue;
      }
      if (char == '"') {
        index++;
        break;
      }
      buffer.write(char);
      index++;
    }
    yield _Literal(start, buffer.toString());
  }
}

String _stripComments(
  String source, {
  required String lineComment,
  required bool blockComment,
  required bool singleQuoteStrings,
}) {
  final output = StringBuffer();
  var index = 0;
  String? quote;
  while (index < source.length) {
    final char = source[index];
    if (quote != null) {
      output.write(char);
      if (char == r'\') {
        if (index + 1 < source.length) {
          output.write(source[index + 1]);
          index += 2;
          continue;
        }
      } else if (char == quote) {
        quote = null;
      }
      index++;
      continue;
    }
    if (char == '"' || (singleQuoteStrings && char == "'")) {
      quote = char;
      output.write(char);
      index++;
      continue;
    }
    if (source.startsWith(lineComment, index)) {
      while (index < source.length && source[index] != '\n') {
        output.write(' ');
        index++;
      }
      continue;
    }
    if (blockComment && source.startsWith('/*', index)) {
      while (index < source.length && !source.startsWith('*/', index)) {
        output.write(source[index] == '\n' ? '\n' : ' ');
        index++;
      }
      if (index < source.length) {
        output.write('  ');
        index += 2;
      }
      continue;
    }
    output.write(char);
    index++;
  }
  return output.toString();
}
