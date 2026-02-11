import 'dart:math';

import 'package:minithesis_dart/src/minithesis.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

void main() {
  test('trivial', () {
    runTest()!(TestFunction('trivial', (tc) {}));
  });

  test('simple integer test passes', () {
    runTest()!(TestFunction('simple integer test passes', (tc) {
      int x = tc.choice(10);
      int y = tc.choice(10);
      check(min(x, y))
          ..isLessOrEqual(x)
          ..equals(y);
    }));
  });
}