import 'dart:collection';
import 'dart:io';

import 'package:stack/stack.dart';

class ParserEvents {
  static void init() {}

  static void onParseBegin(String s) {}

  static void onParseEnd(Object result) {}
}

class YyLoc {
  YyLoc(
    this.startOffset,
    this.endOffset,
    this.startLine,
    this.endLine,
    this.startColumn,
    this.endColumn,
  );

  factory YyLoc.yyloc(YyLoc? start, YyLoc? end) {
    assert(start != null || end != null);

    if (start == null || end == null) {
      return start == null ? end! : start!;
    }

    return YyLoc(
      start.startOffset,
      end.endOffset,
      start.startLine,
      end.endLine,
      start.startColumn,
      end.endColumn,
    );
  }

  int startOffset;
  int endOffset;
  int startLine;
  int endLine;
  int startColumn;
  int endColumn;
}

class Token {
  Token(this.type, this.value, [this.loc]);

  int type;
  String value;
  YyLoc? loc;

  @override
  String toString() => '{type: $type, value: $value}';
}

class Tokenizer {
  Tokenizer(this.tokenizingString);

  String tokenizingString;
  int mCursor = 0;

  Stack<String> mStates = Stack<String>();

  Queue<String>? _mTokensQueue;

  int mCurrentLine = 1;
  int mCurrentColumn = 0;
  int mCurrentLineBeginOffset = 0;

  int mTokenStartOffset = 0;
  int mTokenEndOffset = 0;
  int mTokenStartLine = 0;
  int mTokenEndLine = 0;
  int mTokenStartColumn = 0;
  int mTokenEndColumn = 0;

  String? yytext;
  int yyleng = 0;
  static String eof = '\$';
  static final Map<String, int> _mTokensMap = <String, int>{
    '+': 1,
    '*': 2,
    'NUMBER': 3,
    '(': 4,
    ')': 5,
    '\$': 6,
  };
  static Token eofToken = Token(_mTokensMap[eof]!, eof);
  static final List<RegExp> _mLexPatterns = [
    RegExp(r'^\s+'),
    RegExp(r'^\d+'),
    RegExp(r'^\*'),
    RegExp(r'^\+'),
    RegExp(r'^\('),
    RegExp(r'^\)'),
  ];

  static final List<String? Function(Tokenizer)> _mLexHandlerMethods = [
    (t) => t._lexRule0(),
    (t) => t._lexRule1(),
    (t) => t._lexRule2(),
    (t) => t._lexRule3(),
    (t) => t._lexRule4(),
    (t) => t._lexRule5(),
  ];

  static final RegExp nlRe = RegExp(r'\n');

  static final Map<String, List<int>> _mLexRulesByCondition =
      <String, List<int>>{
        "INITIAL": [0, 1, 2, 3, 4, 5],
      };

  String? _lexRule0() => null;
  String? _lexRule1() => 'NUMBER';
  String? _lexRule2() => '*';
  String? _lexRule3() => '+';
  String? _lexRule4() => '(';
  String? _lexRule5() => ')';
}
