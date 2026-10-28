// ignore_for_file: depend_on_referenced_packages

import 'package:flutter_test/flutter_test.dart';

import 'media_viewer.dart';

void main() {
  test('filenames are decoded exactly once', () {
    expect(mediaFileName('https://example.com/100%25.png'), '100%.png');
    expect(mediaFileName('https://example.com/a%2520b.png'), 'a%20b.png');
    expect(mediaFileName('https://example.com/%E7%8C%AB.png'), '猫.png');
    expect(mediaFileName('https://example.com/'), '');
  });
}
