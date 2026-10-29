// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'message_content.dart';

void main() {
  Widget buildFrame(Widget child) {
    return MaterialApp(home: Scaffold(body: child));
  }

  group('MessageContent standard Markdown rendering', () {
    testWidgets('plain text renders correctly in MarkdownBody', (tester) async {
      await tester.pumpWidget(
        buildFrame(
          const MessageContent(
            text: 'Hello world',
            style: TextStyle(fontSize: 14),
          ),
        ),
      );
      expect(find.byType(MarkdownBody), findsOneWidget);
      expect(find.text('Hello world', findRichText: true), findsOneWidget);
    });

    testWidgets('Markdown bold, italic, code and links render correctly', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildFrame(
          const MessageContent(
            text: '**bold** and *italic* and `code` and [link](https://flspeak.org)',
            style: TextStyle(fontSize: 14),
          ),
        ),
      );
      expect(find.byType(MarkdownBody), findsOneWidget);
      expect(find.textContaining('bold', findRichText: true), findsOneWidget);
      expect(find.textContaining('italic', findRichText: true), findsOneWidget);
      expect(find.textContaining('code', findRichText: true), findsOneWidget);
      expect(find.textContaining('link', findRichText: true), findsOneWidget);
    });

    testWidgets(
      'Markdown blocks (headings, blockquotes, lists, hr) render correctly',
      (tester) async {
        const content = '''
# Heading 1
> A wise quote
- Item 1
- Item 2
---
''';
        await tester.pumpWidget(
          buildFrame(
            const MessageContent(text: content, style: TextStyle(fontSize: 14)),
          ),
        );
        expect(find.byType(MarkdownBody), findsOneWidget);
        expect(
          find.textContaining('Heading 1', findRichText: true),
          findsOneWidget,
        );
        expect(
          find.textContaining('A wise quote', findRichText: true),
          findsOneWidget,
        );
        expect(
          find.textContaining('Item 1', findRichText: true),
          findsOneWidget,
        );
        expect(
          find.textContaining('Item 2', findRichText: true),
          findsOneWidget,
        );
      },
    );
  });
}
