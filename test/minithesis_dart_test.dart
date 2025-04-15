import 'package:minithesis_dart/minithesis.dart';
import 'package:parameterized_test/parameterized_test.dart';
import 'package:test/test.dart';

Possibility listOfIntegers = Possibility("listOfIntegers", (tc) {
  List<int> result = [];
  while (tc.weighted(0.9).toBool()) {
    result.add(tc.choice(10000));
  }
  return result;
});

void main() {
  parameterizedTest(
    'finds small list',
    List<int>.generate(10, (i) => i),
    runTest()
}
