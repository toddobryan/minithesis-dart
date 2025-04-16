import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:fixnum/fixnum.dart';
import 'package:path/path.dart' as p;

import 'src/better_random.dart';

class NamedFunction<F extends Function> {
  NamedFunction(this.name, this.f);

  final String name;
  final F f;

  F get call => f;
}

// Dart uses 64 bit ints on native, but only 32 bits are reliable on web
final int maxBitLength = 63;

final listEquals = const ListEquality().equals;

mixin Database {
  void operator []=(String key, Uint8List value);

  Uint8List? operator [](String key);

  void remove(String key);
}

void Function(void Function(String, TestCase)) runTest([
  int maxExamples = 100,
  BetterRandom? random,
  Database? database,
  bool quiet = false,
]) {
  void accept(NamedFunction<void Function(TestCase)> test) {
    void markFailuresInteresting(TestCase testCase) {
      try {
        test.call(testCase);
      } catch (e) {
        if (testCase.status != null) {
          rethrow;
        }
        testCase.markStatus(Status.interesting);
      }
    }

    var state = TestingState(
      random ?? BetterRandom.usingClock(),
      markFailuresInteresting,
      maxExamples,
    );

    Database db = database ?? DirectoryDb.fromPath(".minithesis-cache");

    var previousFailure = db[test.name];

    if (previousFailure != null) {
      int l = previousFailure.length;
      List<int> theIs = List<int>.generate(l ~/ 8, (x) => x * 8);
      List<Int64> choices = [
        for (int i in theIs)
          Int64.fromBytes(previousFailure.sublist(i, min(l, i + 8))),
      ];
      state.testFunction(TestCase.forChoices(choices));
    }
  }
}

class TestCase {
  TestCase(
    this.prefix,
    this.random, [
    this.maxSize = double.infinity,
    this.printResults = false,
  ]);

  factory TestCase.forChoices(
    List<Int64> choices, [
    bool printResults = false,
  ]) {
    return TestCase(choices, null, choices.length, printResults);
  }

  Iterable<Int64> prefix;
  BetterRandom? random;
  num maxSize = double.infinity;
  bool printResults = false;
  List<Int64> choices = List<Int64>.empty();
  Status? status;
  int depth = 0;
  int? targetingScore;

  int choice(int n) {
    int result = _makeChoice(n, () => random!.nextNonNegIntBelow(n + 1));
    if (_shouldPrint()) {
      print('choice($n): $result');
    }
    return result;
  }

  int weighted(double p) {
    int result =
        p <= 0
            ? forcedChoice(0)
            : (p >= 1
                ? forcedChoice(1)
                : _makeChoice(1, () => (random!.nextDouble() <= p).toInt()));
    if (_shouldPrint()) {
      print('weighted($p): $result');
    }
    return result;
  }

  int forcedChoice(int n) {
    if (n < 0 || n.bitLength >= maxBitLength) {
      throw ArgumentError('Invalid choice $n');
    } else if (status != null) {
      throw Frozen();
    } else if (choices.length >= maxSize) {
      markStatus(Status.overrun);
    }
    choices.add(n);
    return n;
  }

  Never reject() => markStatus(Status.invalid);

  void assume(bool precondition) {
    if (!precondition) {
      reject();
    }
  }

  void target(int score) {
    targetingScore = score;
  }

  U any<U>(Possibility<U> possibility) {
    late U result;
    try {
      depth += 1;
      result = possibility.produce(this);
    } finally {
      depth -= 1;
    }

    if (_shouldPrint()) {
      print('any($possibility): $result');
    }
    return result;
  }

  Never markStatus(Status newStatus) {
    if (status != null) {
      throw Frozen();
    }
    status = newStatus;
    throw StopTest();
  }

  bool _shouldPrint() => printResults && depth == 0;

  int _makeChoice(int n, Int64 Function() rndMethod) {
    late Int64 result;
    if (n < 0 || n.bitLength >= maxBitLength) {
      throw ArgumentError('Invalid choice $n');
    } else if (status != null) {
      throw Frozen();
    } else if (choices.length >= maxSize) {
      markStatus(Status.overrun);
    } else if (choices.length < prefix.length) {
      result = prefix.elementAt(choices.length);
    } else {
      result = rndMethod();
    }
    choices.add(result);

    if (result > n) {
      markStatus(Status.invalid);
    }
    return result;
  }
}

extension IntToBool on int {
  bool toBool() {
    if (this == 0) {
      return false;
    } else if (this == 1) {
      return true;
    } else {
      throw ArgumentError('toBool() only defined for 0 and 1, given: $this');
    }
  }
}

extension BoolToInt on bool {
  int toInt() => this ? 1 : 0;
}

class Possibility<T> {
  Possibility(this.name, this.produce);

  String name;
  T Function(TestCase) produce;

  @override
  String toString() => name;

  Possibility<S> map<S>(S Function(T) f, String name) {
    return Possibility(
      '${this.name}.map($name, (p) => f(p.any(this)))',
      (tc) => f(tc.any(this)),
    );
  }

  Possibility<S> bind<S>(Possibility<S> Function(T) f, String name) {
    S produce(TestCase testCase) {
      return testCase.any(f(testCase.any(this)));
    }

    return Possibility('${this.name}.bind($name, produce)', produce);
  }

  Possibility<T> satisfying(bool Function(T) f, String name) {
    T produce(TestCase testCase) {
      for (int i = 0; i < 3; i++) {
        var candidate = testCase.any(this);
        if (f(candidate)) {
          return candidate;
        }
      }
      testCase.reject();
    }

    return Possibility<T>('${this.name}.select($name)', produce);
  }
}

Possibility<int> integers(int m, int n) {
  return Possibility('integers($m, $n)', (tc) => m + tc.choice(n - m));
}

Possibility<List<U>> lists<U>(
  Possibility<U> elements, [
  int minSize = 0,
  num maxSize = double.infinity,
]) {
  List<U> produce(TestCase testCase) {
    List<U> result = List<U>.empty();
    while (true) {
      if (result.length < minSize) {
        testCase.forcedChoice(1);
      } else if (result.length + 1 >= maxSize) {
        testCase.forcedChoice(0);
        break;
      } else if (!testCase.weighted(0.9).toBool()) {
        break;
      }
      result.add(testCase.any(elements));
    }
    return result;
  }

  return Possibility<List<U>>('lists(${elements.name})', produce);
}

Possibility<U> just<U>(U value) {
  return Possibility<U>('just($value)', (tc) => value);
}

Possibility<Never> nothing() {
  return Possibility('nothing()', (tc) => tc.reject());
}

Possibility<T> mixOf<T>(List<Possibility<T>> possibilities) {
  if (possibilities.isEmpty) {
    return nothing();
  }
  return Possibility(
    'mixOf(${possibilities.map((p) => p.name).join(', ')})',
    (tc) => tc.any(possibilities[tc.choice(possibilities.length - 1)]),
  );
}

Possibility<(T, U)> tuple2<T, U>(Possibility<T> t, Possibility<U> u) {
  return Possibility(
    'tuples(${t.name}, ${u.name})',
    (tc) => (tc.any(t), tc.any(u)),
  );
}

Possibility<(T, U, V)> tuple3<T, U, V>(
  Possibility<T> t,
  Possibility<U> u,
  Possibility<V> v,
) {
  return Possibility(
    'tuples(${t.name}, ${u.name}, ${v.name})',
    (tc) => (tc.any(t), tc.any(u), tc.any(v)),
  );
}

Possibility<(T1, T2, T3, T4)> tuple4<T1, T2, T3, T4>(
  Possibility<T1> t1,
  Possibility<T2> t2,
  Possibility<T3> t3,
  Possibility<T4> t4,
) {
  return Possibility(
    'tuples(${t1.name}, ${t2.name}, ${t3.name}, ${t4.name})',
    (tc) => (tc.any(t1), tc.any(t2), tc.any(t3), tc.any(t4)),
  );
}

Possibility<(T1, T2, T3, T4, T5)> tuple5<T1, T2, T3, T4, T5>(
  Possibility<T1> t1,
  Possibility<T2> t2,
  Possibility<T3> t3,
  Possibility<T4> t4,
  Possibility<T5> t5,
) {
  return Possibility(
    'tuples(${t1.name}, ${t2.name}, ${t3.name}, ${t4.name}, ${t5.name})',
    (tc) => (tc.any(t1), tc.any(t2), tc.any(t3), tc.any(t4), tc.any(t5)),
  );
}

final int bufferSize = 8 * 1024;

(int, List<int>) sortKey(List<int> choices) => (choices.length, choices);

class CachedTestFunction {
  CachedTestFunction(this.testFunction);

  void Function(TestCase) testFunction;
  Map<int, dynamic> tree = <int, dynamic>{};

  Status call(List<int> choices) {
    dynamic node = tree;
    for (int c in choices) {
      node = node[c];
      if (node == null) {
        break;
      }
      if (node is Status) {
        assert(node != Status.overrun);
        return node;
      }
    }
    if (node == null) {
      return Status.overrun;
    }

    TestCase testCase = TestCase.forChoices(choices);
    testFunction(testCase);
    assert(testCase.status != null);

    node = tree;
    for (final (i, c) in testCase.choices.indexed) {
      if (i + 1 < testCase.choices.length ||
          testCase.status == Status.overrun) {
        if (!(node as Map<int, dynamic>).containsKey(c)) {
          node[c] = <int, dynamic>{};
        }
        node = node[c];
      } else {
        node[c] = testCase.status;
      }
    }
    return testCase.status!;
  }
}

class TestingState {
  TestingState(this.random, this.testFunction, this.maxExamples);

  BetterRandom random;
  int maxExamples;
  void Function(TestCase) testFunction;
  int validTestCases = 0;
  int calls = 0;
  List<int>? result;
  (int, List<int>)? bestScoring;
  bool testIsTrivial = false;

  void callTestFunction(TestCase testCase) {
    try {
      testFunction(testCase);
    } on StopTest {
      // do nothing
    }

    testCase.status ??= Status.valid;
    calls++;

    if (testCase.choices.isEmpty &&
        testCase.status!.val >= Status.invalid.val) {
      testIsTrivial = true;
    }

    if (testCase.status!.val >= Status.valid.val) {
      validTestCases++;

      if (testCase.targetingScore != null) {
        (int, List<int>) relevantInfo = (
          testCase.targetingScore!,
          testCase.choices,
        );
        if (bestScoring == null) {
          bestScoring = relevantInfo;
        } else {
          late int best;
          (best, _) = bestScoring!;
          if (testCase.targetingScore! > best) {
            bestScoring = relevantInfo;
          }
        }
      }
    }

    if (testCase.status == Status.interesting &&
        (result == null || sortKey(testCase.choices) < sortKey(result!))) {
      result = testCase.choices;
    }
  }

  void target() {
    if (result != null || bestScoring == null) {
      return;
    }

    bool adjust(int i, int step) {
      assert(bestScoring != null);
      var (int score, List<int> choices) = bestScoring!;
      if (choices[i] + step < 0 || choices[i].bitLength >= maxBitLength) {
        return false;
      }

      List<int> attempt = [...choices];
      attempt[i] += step;
      TestCase testCase = TestCase(attempt, random, bufferSize);
      callTestFunction(testCase);
      assert(testCase.status != null);
      return (testCase.status!.val >= Status.valid.val &&
          testCase.targetingScore != null &&
          testCase.targetingScore! > score);
    }

    while (shouldKeepGenerating()) {
      int i = random.nextIntInRange(0, bestScoring!.$2.length);
      int sign = 0;
      for (int k in [1, -1]) {
        if (!shouldKeepGenerating()) {
          return;
        }
        if (adjust(i, k)) {
          sign = k;
          break;
        }
      }
      if (sign == 0) {
        continue;
      }

      int k = 1;
      while (shouldKeepGenerating() && adjust(i, sign * k)) {
        k *= 2;
      }

      while (k > 0) {
        while (shouldKeepGenerating() && adjust(i, sign * k)) {
          // do nothing
        }
        k ~/= 2;
        {}
      }
    }
  }

  void run() {
    generate();
    target();
    shrink();
  }

  bool shouldKeepGenerating() {
    return (!testIsTrivial &&
        result == null &&
        validTestCases < maxExamples &&
        calls < maxExamples * 10);
  }

  void generate() {
    while (shouldKeepGenerating() && bestScoring == null ||
        validTestCases <= maxExamples ~/ 2) {
      callTestFunction(TestCase([], random, bufferSize));
    }
  }

  void shrink() {
    if (result == null || result!.isEmpty) {
      return;
    }

    CachedTestFunction cached = CachedTestFunction(testFunction);

    bool consider(List<int> choices) {
      if (listEquals(choices, result)) {
        return true;
      } else {
        return cached(choices) == Status.interesting;
      }
    }

    assert(consider(result!));

    List<int>? prev;

    while (!listEquals(prev, result)) {
      prev = [...result!];

      int k = 8;
      while (k > 0) {
        int i = result!.length - k - 1;
        while (i >= 0) {
          if (i >= result!.length) {
            i -= 1;
            continue;
          }
          List<int> attempt = result!.sublist(0, i) + result!.sublist(i + k);
          assert(attempt.length < result!.length);
          if (!consider(attempt)) {
            if (i > 0 && attempt[i - 1] > 0) {
              attempt[i - 1]--;
              if (consider(attempt)) {
                i++;
              }
            }
            i--;
          }
        }
        k--;
      }

      bool replace(Map<int, int> values) {
        assert(result != null);
        List<int> attempt = [...result!];
        for (var me in values.entries) {
          if (me.key >= attempt.length) {
            return false;
          }
          attempt[me.key] = me.value;
        }
        return consider(attempt);
      }

      k = 8;
      while (k > 1) {
        int i = result!.length - k;
        while (i >= 0) {
          Map<int, int> kZerosStartingAtI = <int, int>{
            for (int j in List<int>.generate(k, (x) => i + x)) j: 0,
          };
          if (replace(kZerosStartingAtI)) {
            i -= k;
          } else {
            i--;
          }
        }
        k--;
      }

      int i = result!.length - 1;
      while (i >= 0) {
        binSearchDown(0, result![i], (v) => replace(<int, int>{i: v}));
        i--;
      }

      k = 8;
      while (k > 1) {
        List<int> range = [for (int x = result!.length - k - 1; x > -1; x--) x];
        for (i in range) {
          List<int> middle = [...result!.sublist(i, i + k)];
          middle.sort();
          consider(result!.sublist(0, i) + middle + result!.sublist(i + k));
        }
        k--;
      }

      for (k in [2, 1]) {
        List<int> range = [for (int x = result!.length - k - 1; x > -1; x--) x];
        for (i in range) {
          int j = i + k;

          if (j < result!.length) {
            if (result![i] == result![j]) {
              replace(<int, int>{j: result![i], i: result![j]});
            }
            if (j < result!.length && result![i] > 0) {
              int previousI = result![i];
              int previousJ = result![j];
              binSearchDown(
                0,
                previousI,
                (v) =>
                    replace(<int, int>{i: v, j: (previousJ + (previousI - v))}),
              );
            }
          }
        }
      }
    }
  }
}

int binSearchDown(int lo, int hi, bool Function(int) f) {
  if (f(lo)) {
    return lo;
  }
  while (lo + 1 < hi) {
    int mid = lo + (hi - lo) ~/ 2;
    if (f(mid)) {
      hi = mid;
    } else {
      lo = mid;
    }
  }
  return hi;
}

extension CompareIntList on (int, List<int>) {
  bool operator <((int, List<int>) other) {
    if ($1 < other.$1) {
      return true;
    } else if ($1 > other.$1) {
      return false;
    } else {
      for (int i = 0; i < max($2.length, other.$2.length); i++) {
        if (i > $2.length) {
          return true;
        } else if (i > other.$2.length) {
          return false;
        } else if ($2[i] < other.$2[i]) {
          return true;
        } else if ($2[i] > other.$2[i]) {
          return false;
        }
      }
      return false;
    }
  }
}

class DirectoryDb implements Database {
  DirectoryDb(this.directory);

  factory DirectoryDb.fromPath(String path) {
    Directory dir = Directory(path);
    if (!dir.existsSync()) {
      dir.createSync();
    }
    return DirectoryDb(dir);
  }

  Directory directory;

  File _toFile(String key) {
    String filename = sha1
        .convert(utf8.encode(key))
        .toString()
        .substring(0, 10);
    return File(p.join(directory.path, filename));
  }

  @override
  Uint8List? operator [](String key) {
    var f = _toFile(key);
    if (!f.existsSync()) {
      return null;
    }
    return f.readAsBytesSync();
  }

  @override
  void operator []=(String key, Uint8List value) {
    var f = _toFile(key);
    f.writeAsBytesSync(value);
  }

  @override
  void remove(String key) {
    var f = _toFile(key);
    f.deleteSync();
  }
}

class Frozen extends Error {}

class StopTest extends Error {}

class Unsatisfiable extends Error {}

enum Status {
  overrun(0),
  invalid(1),
  valid(2),
  interesting(3);

  const Status(this.val);

  final int val;
}
