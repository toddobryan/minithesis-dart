import 'dart:collection';
import 'dart:io';

import 'package:stack/stack.dart';

class ParserEvents {
  static void init() {}

  static void onParseBegin(String s) {}

  static void onParseEnd(Object? result) {}
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

  @override
  String toString() => "(start: $startOffset, end: $endOffset)";
}

class Token {
  Token(this.type, this.value, [this.loc]);

  int type;
  String value;
  YyLoc? loc;

  @override
  String toString() => '{type: $type, value: $value, loc: $loc}';
}

class Tokenizer {
  Tokenizer() : mString = null;

  Tokenizer.fromString(String tokenizingString) {
    initString(tokenizingString);
  }

  String? mString;
  int mCursor = 0;

  Stack<String> mStates = Stack<String>();

  Queue<String> mTokensQueue = Queue<String>.of(['INITIAL']);

  int mCurrentLine = 1;
  int mCurrentColumn = 0;
  int mCurrentLineBeginOffset = 0;

  int mTokenStartOffset = 0;
  int mTokenEndOffset = 0;
  int mTokenStartLine = 0;
  int mTokenEndLine = 0;
  int mTokenStartColumn = 0;
  int mTokenEndColumn = 0;

  void initString(String tokenizingString) {
    mString = tokenizingString;
    mCursor = 0;

    mStates = Stack<String>();
    begin('INITIAL');

    mTokensQueue = Queue<String>();

    mCurrentLine = 1;
    mCurrentColumn = 0;
    mCurrentLineBeginOffset = 0;

    mTokenStartOffset = 0;
    mTokenEndOffset = 0;
    mTokenEndLine = 0;
    mTokenEndColumn = 0;
  }

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

  String getCurrentState() => mStates.top();

  void pushState(String state) => mStates.push(state);

  void begin(String state) => pushState(state);

  String popState() {
    if (mStates.size() > 1) {
      return mStates.pop();
    } else {
      return getCurrentState();
    }
  }

  Token? getNextToken() {
    if (mTokensQueue.isNotEmpty) {
      return toToken(mTokensQueue.removeFirst(), '');
    } else if (!hasMoreTokens()) {
      return eofToken;
    }

    String str = mString!.substring(mCursor);
    List<int> lexRulesForState = _mLexRulesByCondition[getCurrentState()]!;

    for (int i = 0; i < lexRulesForState.length; i++) {
      String? matched = match(str, _mLexPatterns[i]);
      if (str.length == 0 && matched != null && matched.length == 0) {
        mCursor++;
      }

      if (matched != null) {
        yytext = matched;
        yyleng = matched.length;

        Object? tokenType;
        tokenType = _mLexHandlerMethods[i](this);

        if (tokenType == null) {
          return getNextToken();
        }

        if (tokenType is List) {
          List<String> tokensList = tokenType as List<String>;
          tokenType = tokensList[0];
          if (tokensList.length > 1) {
            for (int j = 1; j < tokensList.length; j++) {
              mTokensQueue.add(tokensList[j]);
            }
          }
        }

        return toToken(tokenType as String, matched);
      }
    }

    if (isEof()) {
      mCursor++;
      return eofToken;
    }

    throwUnexpectedToken(
      String.fromCharCode(str.codeUnitAt(0)),
      mCurrentLine,
      mCurrentColumn,
    );

    return null;
  }

  void throwUnexpectedToken(String symbol, int line, int column) {
    String lineSource = mString!.split('\n')[line - 1];

    String pad = " " * column;
    String lineData = '\n\n$lineSource\n$pad^\n';

    throw ParseException(
      '${lineData}Unexpected token: "$symbol" at $line:$column.',
      0,
    );
  }

  void captureLocation(String? matched) {
    if (matched == null) {
      return;
    }

    mTokenStartOffset = mCursor;

    mTokenStartLine = mCurrentLine;
    mTokenStartColumn = mTokenStartOffset - mCurrentLineBeginOffset;
    Iterable<RegExpMatch> nlMatcher = nlRe.allMatches(matched);
    for (RegExpMatch nlMatch in nlMatcher) {
      mCurrentLine++;
      mCurrentLineBeginOffset = mTokenStartOffset + nlMatch.start + 1;
    }
    mTokenEndOffset = mCursor + matched.length;

    mTokenEndLine = mCurrentLine;
    mTokenEndColumn = mTokenEndOffset - mCurrentLineBeginOffset;
    mCurrentColumn = mTokenEndColumn;
  }

  Token toToken(String tokenType, String yytext) {
    return Token(
      _mTokensMap[tokenType]!,
      yytext,
      YyLoc(
        mTokenStartOffset,
        mTokenEndOffset,
        mTokenStartLine,
        mTokenEndLine,
        mTokenStartColumn,
        mTokenEndColumn,
      ),
    );
  }

  bool hasMoreTokens() => mCursor <= mString!.length;

  bool isEof() => mCursor == mString!.length;

  String? match(String str, RegExp re) {
    String? v = re.matchAsPrefix(str)?.group(0); // maybe should be just match
    captureLocation(v);
    if (v != null) {
      mCursor += v.length;
    }
    return v;
  }

  String get() => mString!;
}

class StackEntry {
  StackEntry(this.symbol, this.semanticValue, this.loc);

  int symbol;
  Object? semanticValue;
  YyLoc? loc;
}

class CalcParser {
  CalcParser() {
    ParserEvents.init();
  }

  Tokenizer tokenizer = Tokenizer();

  static List<List<int>> mProductions = [
    [-1, -1],
    [0, 3],
    [0, 3],
    [0, 1],
    [0, 3],
  ];

  static final List<void Function(CalcParser)> mProductionHandlerMethods = [
    (cp) => cp.handler0(),
    (cp) => cp.handler1(),
    (cp) => cp.handler2(),
    (cp) => cp.handler3(),
    (cp) => cp.handler4(),
  ];

  static final List<Map<int, String>> mTable = [
    {0: "1", 3: "s2", 4: "s3"},
    {1: "s4", 2: "s5", 6: "acc"},
    {1: "r3", 2: "r3", 5: "r3", 6: "r3"},
    {0: "8", 3: "s2", 4: "s3"},
    {0: "6", 3: "s2", 4: "s3"},
    {0: "7", 3: "s2", 4: "s3"},
    {1: "r1", 2: "s5", 5: "r1", 6: "r1"},
    {1: "r2", 2: "r2", 5: "r2", 6: "r2"},
    {1: "s4", 2: "s5", 5: "s9"},
    {1: "r4", 2: "r4", 5: "r4", 6: "r4"},
  ];

  Stack<StackEntry> mValueStack = Stack<StackEntry>();

  Stack<int> mStatesStack = Stack<int>();

  StackEntry? __;

  void handler0() {
    StackEntry _1 = mValueStack!.pop();
    __!.semanticValue = _1.semanticValue;
  }

  void handler1() {
    StackEntry _3 = mValueStack.pop();
    mValueStack.pop();
    StackEntry _1 = mValueStack.pop();

    __!.semanticValue = (_1.semanticValue as int) + (_3.semanticValue as int);
  }

  void handler2() {
    StackEntry _3 = mValueStack.pop();
    mValueStack.pop();
    StackEntry _1 = mValueStack.pop();

    __!.semanticValue = (_1.semanticValue as int) * (_3.semanticValue as int);
  }

  void handler3() {
    mValueStack.pop();

    __!.semanticValue = int.parse(tokenizer.yytext!);
  }

  void handler4() {
    mValueStack.pop();
    StackEntry _2 = mValueStack.pop();
    mValueStack.pop();

    __!.semanticValue = _2.semanticValue;
  }

  Object? parse(String str) {
    tokenizer.initString(str);
    ParserEvents.onParseBegin(str);

    mValueStack = Stack<StackEntry>();
    mStatesStack = Stack<int>();
    mStatesStack.push(0);

    Token? token = tokenizer.getNextToken();
    Token? shiftedToken;

    do {
      if (token == null) {
        unexpectedEndOfInput();
      }
      token!;

      int state = mStatesStack.top();
      int column = token.type;

      if (!mTable[state].containsKey(column)) {
        unexpectedToken(token);
        break;
      }

      String entry = mTable[state][column]!;

      if (entry.substring(0, 1) == 's') {
        mValueStack.push(StackEntry(token.type, token.value, token.loc));

        mStatesStack.push(int.parse(entry.substring(1)));

        shiftedToken = token;
        token = tokenizer.getNextToken();
      } else if (entry.substring(0, 1) == 'r') {
        int productionNumber = int.parse(entry.substring(1));
        List<int> production = mProductions[productionNumber];

        int rhsLength = production[1];
        if (rhsLength != 0) {
          while (rhsLength-- > 0) {
            mStatesStack.pop();
          }
        }

        int previousState = mStatesStack.top();
        int symbolToReduceWith = production[0];

        __ = StackEntry(symbolToReduceWith, null, null);

        tokenizer.yytext = shiftedToken?.value;
        tokenizer.yyleng = shiftedToken?.value.length ?? 0;

        mProductionHandlerMethods[productionNumber](this);

        mValueStack.push(__!);

        int nextState = int.parse(mTable[previousState][symbolToReduceWith]!);

        mStatesStack.push(nextState);
      } else if (entry.substring(0, 1) == 'a') {
        mStatesStack.pop();

        StackEntry parsed = mValueStack.pop();

        if (mStatesStack.size() != 1 ||
            mStatesStack.top() != 0 ||
            tokenizer.hasMoreTokens()) {
          unexpectedToken(token);
        }

        Object? parsedValue = parsed.semanticValue;
        ParserEvents.onParseEnd(parsedValue);

        return parsedValue;
      }
    } while (tokenizer.hasMoreTokens() || mStatesStack.size() > 1);

    return null;
  }

  void unexpectedToken(Token token) {
    if (token.type == Tokenizer.eofToken.type) {
      unexpectedEndOfInput();
    }

    tokenizer.throwUnexpectedToken(
      String.fromCharCode(token.value.codeUnitAt(0)),
      token.loc!.startLine,
      token.loc!.startColumn,
    );
  }

  void unexpectedEndOfInput() {
    parseError('Unexpected end of input.');
  }

  void parseError(String message) {
    throw ParseException('Parse error: $message', 0);
  }
}

class ParseException implements Exception {
  ParseException(this.message, this.errorOffset);

  String message;
  int errorOffset;
}

void main() {
  CalcParser calcParser = CalcParser();
  print(calcParser.parse('2 + 2 * 2'));
  print(calcParser.parse('(2 + 2) * 2'));
}
