import 'package:flutter_test/flutter_test.dart';

import 'package:flspeak/core/avatar_input.dart';

void main() {
  test('avatar input accepts the cap and rejects larger lengths', () {
    expect(() => ensureAvatarSize(maxAvatarBytes), returnsNormally);
    expect(
      () => ensureAvatarSize(maxAvatarBytes + 1),
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
