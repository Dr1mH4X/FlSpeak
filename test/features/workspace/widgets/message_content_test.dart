// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flspeak/features/workspace/widgets/message_content.dart';

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

    testWidgets(
      'welcome message renders color, emphasis, nested links and fires link tap',
      (tester) async {
        const text =
            '<color hex="#ff55ff">*Welcome notice*</color> '
            'Portal [https://portal.example.com/](https://portal.example.com/) '
            '<color hex="#ffd700">**Client guide** '
            '[Open guide ](https://docs.example.com/guide)</color>';
        final tappedLinks = <String>[];

        await tester.pumpWidget(
          buildFrame(
            MessageContent(
              text: text,
              style: const TextStyle(fontSize: 14),
              onLinkTap: tappedLinks.add,
            ),
          ),
        );

        bool foundMagentaItalic = false;
        bool foundGoldBold = false;
        TapGestureRecognizer? topLevelLinkRecognizer;
        TapGestureRecognizer? nestedLinkRecognizer;

        void inspectSpan(InlineSpan span) {
          if (span is TextSpan) {
            final content = span.text ?? '';
            if (content.contains('Welcome notice') &&
                span.style?.color == const Color(0xFFFF55FF) &&
                span.style?.fontStyle == FontStyle.italic) {
              foundMagentaItalic = true;
            }
            if (content.contains('Client guide') &&
                span.style?.color == const Color(0xFFFFD700) &&
                span.style?.fontWeight == FontWeight.bold) {
              foundGoldBold = true;
            }
            if (content.contains('https://portal.example.com/') &&
                span.style?.decoration == TextDecoration.underline &&
                span.recognizer is TapGestureRecognizer) {
              topLevelLinkRecognizer = span.recognizer! as TapGestureRecognizer;
            }
            if (content.contains('Open guide') &&
                span.style?.color == const Color(0xFFFFD700) &&
                span.style?.decoration == TextDecoration.underline &&
                span.recognizer is TapGestureRecognizer) {
              nestedLinkRecognizer = span.recognizer! as TapGestureRecognizer;
            }
            if (span.children != null) {
              for (final child in span.children!) {
                inspectSpan(child);
              }
            }
          }
        }

        for (final element in tester.elementList(find.byType(SelectableText))) {
          final st = element.widget as SelectableText;
          if (st.textSpan != null) {
            inspectSpan(st.textSpan!);
          }
        }

        expect(foundMagentaItalic, isTrue);
        expect(foundGoldBold, isTrue);
        expect(topLevelLinkRecognizer, isNotNull);
        expect(nestedLinkRecognizer, isNotNull);

        topLevelLinkRecognizer!.onTap?.call();
        nestedLinkRecognizer!.onTap?.call();
        expect(tappedLinks, [
          'https://portal.example.com/',
          'https://docs.example.com/guide',
        ]);
      },
    );

    testWidgets(
      'preserves single line breaks within paragraphs and separates blocks on blank lines',
      (tester) async {
        const text =
            '<color hex="#ff55ff">*Line one*</color>\n'
            'Line two [https://portal.example.com/](https://portal.example.com/)\n'
            '<color hex="#ffd700">**Line three** [Open guide](https://docs.example.com/guide)</color>\n\n'
            'Section A\n'
            '<color hex="#00aa00">1. First item </color>\n'
            '<color hex="#00aa00">2. Second item</color>';

        await tester.pumpWidget(
          buildFrame(
            const MessageContent(text: text, style: TextStyle(fontSize: 14)),
          ),
        );

        final paragraphTexts = tester
            .widgetList<SelectableText>(find.byType(SelectableText))
            .map((widget) => widget.textSpan?.toPlainText() ?? '')
            .where((plain) => plain.isNotEmpty)
            .toList();

        expect(paragraphTexts.length, greaterThanOrEqualTo(2));
        expect(
          paragraphTexts.any(
            (plain) =>
                plain.contains('Line one\nLine two') &&
                plain.contains(')\nLine three') == false &&
                plain.contains('\nLine three Open guide'),
          ),
          isTrue,
          reason:
              'Single line breaks should remain \\n within a paragraph: $paragraphTexts',
        );
        expect(
          paragraphTexts.any(
            (plain) =>
                plain.contains('Section A\n1. First item \n2. Second item'),
          ),
          isTrue,
          reason:
              'Grouped command lines separated by single \\n should keep \\n: $paragraphTexts',
        );
      },
    );
  });
}
