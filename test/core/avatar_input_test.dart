import 'package:flspeak_ffi/flspeak_ffi.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flspeak/core/avatar_input.dart';

void main() {
  test('avatar input accepts the cap and rejects larger lengths', () {
    final limit = maxAvatarBytes();
    expect(() => ensureAvatarSize(limit), returnsNormally);
    expect(
      () => ensureAvatarSize(limit + 1),
      throwsA(
        isA<AvatarInputException>().having(
          (error) => error.failure,
          'failure',
          AvatarInputFailure.tooLarge,
        ),
      ),
    );
  });
}
