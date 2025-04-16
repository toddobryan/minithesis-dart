import 'dart:math';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';

class BetterRandom {
  static final int minInt32 = -0x80000000;
  static final int maxInt32 = 0x7FFFFFFF;
  static final Int64 minInt64 = Int64.fromInts(-0x80000000, 0);
  static final Int64 maxInt64 = Int64.fromInts(0x7FFFFFFF, 0xFFFFFFFF);
  static final int bitsInInt64 = 64;
  static final int precision = 53;

  BetterRandom(this.seed);

  factory BetterRandom.usingClock() =>
      BetterRandom(Int64(DateTime.now().microsecondsSinceEpoch));

  final Int64 seed;

  _MersenneTwister? __twister;

  _MersenneTwister get _twister {
    if (__twister != null) {
      return __twister!;
    } else {
      __twister = _MersenneTwister(seed);
      return __twister!;
    }
  }

  /// Returns a random Int64 where the first (64 - bits) bits are zero
  /// and the rest are either 0 or 1 at pseudo-random.
  Int64 next(int bits) {
    if (bits == bitsInInt64) {
      return nextInt64();
    } else if (bits <= 0 || bits > bitsInInt64) {
      throw ArgumentError(
        'bits must be in range [1, $bitsInInt64], given: $bits',
      );
    } else {
      return Int64((1 << bits) - 1) & nextInt();
    }
  }

  /// Returns a pseudo-random int
  /// in the range -2^31 to 2^31-1 inclusive.
  int nextInt() {
    return _twister.nextInt64() & minInt32;
  }

  /// Returns a pseudo-random int in the range [min, max),
  /// where max == null acts as if max were 2^31.
  int nextIntInRange(int min, int? max) {
    if (max != null && min >= max) {
      throw ArgumentError("min must be less than max, given: $min, $max");
    } else if (min == minInt && max == null) {
      return nextInt();
    }
    var bound = (max != null ? Int64(max) : maxIntPlusOne) - Int64(min);
    int m = (bound - 1).toInt();
    if ((bound & m) == 0) {
      return (nextInt() & m) + min;
    } else {
      return _nextIntInUniformRange(bound) + min;
    }
  }

  int nextNonNegIntBelow(int bound) {
    if (bound <= 0) {
      throw ArgumentError('bound must be positive, given: $bound');
    } else if (bound == 1) {
      return 0;
    }

    int m = bound - 1;
    if ((bound & m) == 0) {
      // only true if bound is a power of 2
      return nextInt() & m; // equivalent to nextInt() % bound
    } else {
      return _nextIntInUniformRange(Int64(bound)) % bound;
    }
  }

  /// returns a pseudo-random Int64 such that max % n is equally likely for
  /// n in range [0, max].
  Int64 _nextIntInUniformRange(Int64 max) {
    if (max < maxInt64) {
      // we can fit at least two ranges for n % (max + 1) in Int64s
      // eliminate values at each end of the int range where remainders would be
      // over-represented, i.e., we limit ourselves to a range where each
      // remainder occurs the same number of times, namely floor(2^32 / bound)
      Int64 leastMultipleOfBoundAboveMinInt =
          minInt64 + minInt64.remainder(max);
      Int64 maxMultipleOfBoundBelowMaxIntMinusOne =
          maxInt64 - (maxInt64 % max) - 1;
      Int64 r = nextInt64();
      // the worst case for this is 2^30, where only half the values are in the acceptable range
      // so the expected number of times the while loop should run is <= 2
      while (r < leastMultipleOfBoundAboveMinInt ||
          r > maxMultipleOfBoundBelowMaxIntMinusOne) {
        r = nextInt64();
      }
      return r;
    } else {
      // there's only room for one range where each n % bound is equally likely
      // we arbitrarily choose the range centered around zero
      Int64 negBound = -(max >> 1);
      Int64 posBound = ((max >> 1) - max % 2);
      Int64 r = nextInt64();
      while (r < negBound || r > posBound) {
        r = nextInt64();
      }
      return r;
    }
  }

  Int64 nextInt64() {
    return _twister.nextInt64();
  }

  double nextDouble() {
    final int size = 64;
    final int precision = 53;
    return (nextInt64() >>> (size - precision)).toDouble() * pow(2, -53);
  }
}

extension Int64RightShift on Int64 {
  Int64 operator >>>(int shifts) {
    if (shifts >= 64) {
      return Int64(0);
    } else {
      Int64 num = this;
      for (int i = 0; i < shifts; i++) {
        num = (num >> 1) & Int64(0x7FFFFFFFFFFFFFFF);
      }
      return num;
    }
  }
}

class _MersenneTwister {
  static final int n = 624;
  static final int m = 397;
  static final int matrixA = 0x9908b0df;
  static final int upperMask = 0x80000000;
  static final int lowerMask = 0x7FFFFFFF;

  _MersenneTwister(this.seed) {
    List<Int64> temp = [seed];
    for (int i = 1; i < n; i++) {
      Int64 prevTemp = temp[i - 1];
      Int64 nextVal = Int64(1812433253) * prevTemp ^ (prevTemp >>> 30) + i;
      temp.add(nextVal);
    }
    // the toInt in the next line may have trouble in JS, but
    _mt = [...temp];
  }

  final Int64 seed;
  int _index = 0;
  late List<Int64> _mt;

  int nextInt64() {
    if (_index == 0) {
      _generateNumbers();
    }

    Int64 y = _mt[_index];
    y = y ^ (y >> 11);
    y = y ^ ((y << 7) & 0x9D2C5680);
    y = y ^ ((y << 15) & 0xEFC60000);
    y = y ^ (y >> 18);

    _index = (_index + 1) % n;
    return y.toInt();
  }

  void _generateNumbers() {
    for (int i = 0; i < n; i++) {
      int y = (_mt[i] & upperMask) | (_mt[(i + 1) % n] & lowerMask);
      _mt[i] = _mt[(i + m) % n] ^ (y >> 1);
      if ((y % 2) != 0) {
        _mt[i] = _mt[i] ^ matrixA;
      }
    }
  }
}
