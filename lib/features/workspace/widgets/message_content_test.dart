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
    testWidgets('custom color and underline syntax render correctly', (
      tester,
    ) async {
      const text =
          'Normal <color hex="#f44336">red text</color> and <u>underlined text</u> and <color hex="#2196f3">**bold blue**</color>';
      await tester.pumpWidget(
        buildFrame(
          const MessageContent(text: text, style: TextStyle(fontSize: 14)),
        ),
      );
      expect(find.byType(MarkdownBody), findsOneWidget);
      expect(
        find.textContaining('red text', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('underlined text', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('bold blue', findRichText: true),
        findsOneWidget,
      );

      // Verify the TextSpan styles on SelectableText widgets
      final selectableFinder = find.byType(SelectableText);
      expect(selectableFinder, findsWidgets);

      bool foundRed = false;
      bool foundUnderline = false;
      bool foundBoldBlue = false;

      void checkSpan(InlineSpan span) {
        if (span is TextSpan) {
          if (span.text?.contains('red text') ?? false) {
            if (span.style?.color == const Color(0xFFF44336)) {
              foundRed = true;
            }
          }
          if (span.text?.contains('underlined text') ?? false) {
            if (span.style?.decoration == TextDecoration.underline) {
              foundUnderline = true;
            }
          }
          if (span.text?.contains('bold blue') ?? false) {
            if (span.style?.color == const Color(0xFF2196F3) &&
                span.style?.fontWeight == FontWeight.bold) {
              foundBoldBlue = true;
            }
          }
          if (span.children != null) {
            for (final child in span.children!) {
              checkSpan(child);
            }
          }
        }
      }

      for (final element in tester.elementList(selectableFinder)) {
        final st = element.widget as SelectableText;
        if (st.textSpan != null) {
          checkSpan(st.textSpan!);
        }
      }

      expect(foundRed, isTrue, reason: 'Should find span with color #F44336');
      expect(
        foundUnderline,
        isTrue,
        reason: 'Should find span with TextDecoration.underline',
      );
      expect(
        foundBoldBlue,
        isTrue,
        reason: 'Should find span with color #2196F3 and bold',
      );
    });
  });
}
