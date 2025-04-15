import 'dart:math';
import 'dart:typed_data';

import 'src/better_random.dart';

mixin Database {
  void operator []=(String key, ByteData value);

  ByteData? operator [](String key);

  void remove(String key);
}

class TestCase {
  TestCase(
    this.prefix,
    this.random, [
    this.maxSize = double.infinity,
    this.printResults = false,
  ]);

  factory TestCase.forChoices(List<int> choices, [bool printResults = false]) {
    return TestCase(choices, null, choices.length, printResults);
  }

  Iterable<int> prefix;
  BetterRandom? random;
  num maxSize = double.infinity;
  bool printResults = false;
  List<int> choices = List<int>.empty();
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
    if (n < 0 || n.bitLength >= 63) {
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

  int _makeChoice(int n, int Function() rndMethod) {
    late int result;
    if (n < 0 || n.bitLength >= 63) {
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
  Possibility(this.produce, this.name);

  T Function(TestCase) produce;
  String name;

  @override
  String toString() => name;

  Possibility<S> map<S>(S Function(T) f, String name) {
    return Possibility((p) => f(p.any(this)), '${this.name}.map($name)');
  }

  Possibility<S> bind<S>(Possibility<S> Function(T) f, String name) {
    S produce(TestCase testCase) {
      return testCase.any(f(testCase.any(this)));
    }

    return Possibility(produce, '${this.name}.bind($name)');
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

    return Possibility<T>(produce, '${this.name}.select($name)');
  }
}

Possibility<int> integers(int m, int n) {
  return Possibility((tc) => m + tc.choice(n - m), 'integers($m, $n)');
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

  return Possibility<List<U>>(produce, 'lists(${elements.name})');
}

Possibility<U> just<U>(U value) {
  return Possibility<U>((tc) => value, 'just($value)');
}

Possibility<Never> nothing() {
  return Possibility((tc) => tc.reject(), 'nothing()');
}

Possibility<T> mixOf<T>(List<Possibility<T>> possibilities) {
  if (possibilities.isEmpty) {
    return nothing();
  }
  return Possibility(
    (tc) => tc.any(possibilities[tc.choice(possibilities.length - 1)]),
    'mixOf(${possibilities.map((p) => p.name).join(', ')})',
  );
}

Possibility<(T, U)> tuple2<T, U>(Possibility<T> t, Possibility<U> u) {
  return Possibility(
    (tc) => (tc.any(t), tc.any(u)),
    'tuples(${t.name}, ${u.name})',
  );
}

Possibility<(T, U, V)> tuple3<T, U, V>(
  Possibility<T> t,
  Possibility<U> u,
  Possibility<V> v,
) {
  return Possibility(
    (tc) => (tc.any(t), tc.any(u), tc.any(v)),
    'tuples(${t.name}, ${u.name}, ${v.name})',
  );
}

Possibility<(T1, T2, T3, T4)> tuple4<T1, T2, T3, T4>(
  Possibility<T1> t1,
  Possibility<T2> t2,
  Possibility<T3> t3,
  Possibility<T4> t4,
) {
  return Possibility(
    (tc) => (tc.any(t1), tc.any(t2), tc.any(t3), tc.any(t4)),
    'tuples(${t1.name}, ${t2.name}, ${t3.name}, ${t4.name})',
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
    (tc) => (tc.any(t1), tc.any(t2), tc.any(t3), tc.any(t4), tc.any(t5)),
    'tuples(${t1.name}, ${t2.name}, ${t3.name}, ${t4.name}, ${t5.name})',
  );
}

final int bufferSize = 8 * 1024;

(int, List<int>) sortKey(List<int> choices) => (choices.length, choices);

class CachedTestFunction {
  CachedTestFunction(this.testFunction);

  void Function(TestCase) testFunction;
  Map<int, dynamic> tree = <int, dynamic>{};

  Status call(choices = List<int>) {
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
      if (i + 1 < testCase.choices.length || testCase.status == Status.overrun) {
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

    if (testCase.choices.length == 0 
        && testCase.status!.val >= Status.invalid.val) {
      testIsTrivial = true;
    }

    if (testCase.status!.val >= Status.valid.val) {
      validTestCases++;

      if (testCase.targetingScore != null) {
        (int, List<int>) relevantInfo = (testCase.targetingScore!, testCase.choices);
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

    if (testCase.status == Status.interesting 
        && (result == null || sortKey(testCase.choices) < sortKey(result!))) {
      result = testCase.choices;
    }
  }

  void target() {
    
  }
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

