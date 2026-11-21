import 'package:flutter_test/flutter_test.dart';

import 'check_language.dart';

void main() {
  group('scanRust', () {
    test('flags Chinese log, error, expect and assertion messages', () {
      const source = '''
fn demo() {
    log_warn!(error = err.to_string(); "更新失败");
    assert!(ready, "尚未就绪");
}

#[error("连接失败")]
struct Demo;
''';

      final rules = scanRust(
        'core/demo.rs',
        source,
      ).map((violation) => violation.rule).toList();

      expect(rules, contains('log_warn message'));
      expect(rules, contains('assert message'));
      expect(rules, contains('error Display'));
    });

    test('allows Chinese comments and English output', () {
      const source = '''
// 这里记录中文注释。
fn demo() {
    log_warn!("update failed");
    assert!(ready, "not ready");
}
''';

      expect(scanRust('core/demo.rs', source), isEmpty);
    });
  });

  group('scanDart', () {
    test('flags Chinese test output', () {
      const source = '''
void main() {
  testWidgets('连接页面', (tester) async {
    expect(found, isTrue, reason: '应当找到');
    debugPrint('调试输出');
    logWarn('保存失败');
    throw StateError('状态错误');
    assert(false, '断言失败');
  });
}
''';

      final rules = scanDart(
        'test/demo_test.dart',
        source,
      ).map((violation) => violation.rule).toList();

      expect(rules, contains('test description'));
      expect(rules, contains('test reason'));
      expect(rules, contains('debugPrint output'));
      expect(rules, contains('logWarn message'));
      expect(rules, contains('StateError message'));
      expect(rules, contains('assert message'));
    });

    test('flags Chinese tool output', () {
      const source = '''
void main() {
  stderr.writeln('构建失败');
}
''';

      final rules = scanDart(
        'setup.dart',
        source,
      ).map((violation) => violation.rule).toList();

      expect(rules, contains('stderr output'));
    });

    test('allows Chinese UI fixtures and comments', () {
      const source = '''
void main() {
  // 中文注释可以保留。
  testWidgets('renders settings', (tester) async {
    expect(find.text('设置'), findsOneWidget);
  });
}
''';

      expect(scanDart('test/demo_test.dart', source), isEmpty);
    });
  });

  group('scanWorkflow', () {
    test('flags Chinese echo and allows comments', () {
      const source = '''
jobs:
  build:
    steps:
      # 中文注释可以保留。
      - run: echo "构建失败"
''';

      expect(scanWorkflow('.github/workflows/ci.yml', source).length, 1);
    });
  });
}
