import 'dart:async';

import 'package:flutter/foundation.dart';

import 'models/word.dart';
import 'phase.dart';
import 'services/tts_service.dart';

class WordLoopController extends ChangeNotifier {
  WordLoopController({TtsService? ttsService}) : _ttsService = ttsService ?? TtsService() {
    _allWords = _buildInitialWords();
    _currentList = List<Word>.from(_allWords.take(10));
  }

  final TtsService _ttsService;

  late final List<Word> _allWords;
  late List<Word> _currentList;
  final List<Word> _wrongWords = <Word>[];

  Phase _phase = Phase.preview;
  int _index = 0;
  bool _wordVisible = true;
  String _hintText = '';
  int _phaseLoopCount = 0;

  Timer? _timer;
  Timer? _hintFadeTimer;
  Timer? _inputActionTimer;
  bool _hintVisible = true;
  Function(String)? _onInputAction;
  int _errorPosition = -1;
  DateTime _lastRealtimeHintSpeakAt = DateTime.fromMillisecondsSinceEpoch(0);

  Phase get phase => _phase;
  int get index => _index;
  int get total => _currentList.length;
  bool get wordVisible => _wordVisible;
  String get hintText => _hintText;
  bool get hintVisible => _hintVisible;
  int get errorPosition => _errorPosition;

  List<Word> get wrongWords => List<Word>.unmodifiable(_wrongWords);

  Word get currentWord => _currentList[_index];

  int get completedCount => _index;

  int get totalErrors => _allWords.fold<int>(0, (sum, w) => sum + w.errorCount);

  int get masteredCount => _allWords.where((w) => w.errorCount == 0).length;

  double get accuracy {
    final attempts = _allWords.fold<int>(0, (sum, w) => sum + w.attemptCount);
    if (attempts == 0) return 0;
    final errors = _allWords.fold<int>(0, (sum, w) => sum + w.errorCount);
    final correct = attempts - errors;
    if (correct <= 0) return 0;
    return correct / attempts;
  }

  void start() {
    _phase = Phase.preview;
    _index = 0;
    _phaseLoopCount = 0;
    _hintText = '';
    _wordVisible = true;
    _cancelTimer();
    notifyListeners();
    _speakCurrent();
    _scheduleAutoAdvanceIfNeeded();
  }

  @override
  void dispose() {
    _cancelTimer();
    _hintFadeTimer?.cancel();
    _inputActionTimer?.cancel();
    unawaited(_ttsService.dispose());
    super.dispose();
  }

  void next() {
    _hintText = '';
    _errorPosition = -1;
    _inputActionTimer?.cancel();

    if (_phase == Phase.preview) {
      _advanceWithinPhaseOrTransition();
      return;
    }

    if (_phase == Phase.completion) {
      restart();
      return;
    }

    _advanceWithinPhaseOrTransition();
  }

  void skip() {
    if (_phase == Phase.preview || _phase == Phase.spellingInput) {
      _advanceWithinPhaseOrTransition();
    }
  }

  void restart() {
    for (final w in _allWords) {
      w.stage = 0;
      w.errorCount = 0;
      w.inWrongList = false;
      w.priority = 0;
      w.lastAttempt = DateTime.fromMillisecondsSinceEpoch(0);
      w.attemptCount = 0;
      w.isKeyWord = false;
    }
    _wrongWords.clear();
    _currentList = List<Word>.from(_allWords.take(10));
    start();
  }

  Future<void> submit(String input) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return;

    final word = currentWord;
    word.attemptCount += 1;
    word.lastAttempt = DateTime.now();

    final correct = trimmed.toLowerCase() == word.word.toLowerCase();
    if (correct) {
      if (word.inWrongList) {
        word.inWrongList = false;
        _wrongWords.removeWhere((w) => w.id == word.id);
      }
      _hintText = '正确';
      _wordVisible = true;
      notifyListeners();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      _advanceWithinPhaseOrTransition();
      return;
    }

    word.errorCount += 1;
    if (_phase == Phase.recall || _phase == Phase.blindTest || _phase == Phase.wrongReview) {
      _addWrong(word);
    }

    _hintText = _buildHint(word: word, errorCount: word.errorCount, phase: _phase);

    if (_phase == Phase.recall && word.errorCount >= 3) {
      _wordVisible = true;
    }

    if (_phase == Phase.spellingInput && word.errorCount >= 3) {
      _advanceWithinPhaseOrTransition();
    }

    notifyListeners();
  }

  Future<void> playPronunciation() async {
    await _ttsService.speak(currentWord.word);
  }

  void setInputActionCallback(Function(String) callback) {
    _onInputAction = callback;
  }

  void checkInputRealtime(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      _hintText = '';
      _errorPosition = -1;
      notifyListeners();
      return;
    }

    final word = currentWord;
    final targetWord = word.word.toLowerCase();
    final userInput = trimmed.toLowerCase();
    
    // 检查输入是否是目标单词的前缀
    if (targetWord.startsWith(userInput)) {
      // 输入正确，不显示提示
      _hintText = '';
      _errorPosition = -1;
      _inputActionTimer?.cancel();
    } else {
      // 输入错误，找到错误位置
      _errorPosition = _findErrorPosition(userInput, targetWord);
      _hintText = _buildRealtimeHint(word: word, userInput: trimmed);
      _scheduleHintFadeOut();
      _scheduleInputAction(trimmed, word.word);
      _speakRealtimeHintIfNeeded();
    }
    notifyListeners();
  }

  void _speakRealtimeHintIfNeeded() {
    if (_phase != Phase.recall || _wordVisible) {
      return;
    }
    final now = DateTime.now();
    if (now.difference(_lastRealtimeHintSpeakAt) < const Duration(milliseconds: 600)) {
      return;
    }
    _lastRealtimeHintSpeakAt = now;
    unawaited(_ttsService.speak(currentWord.word));
  }

  int _findErrorPosition(String userInput, String targetWord) {
    for (int i = 0; i < userInput.length && i < targetWord.length; i++) {
      if (userInput[i] != targetWord[i]) {
        return i;
      }
    }
    // 如果前面都匹配，但输入长度超过目标单词长度
    if (userInput.length > targetWord.length) {
      return targetWord.length;
    }
    return userInput.length - 1; // 默认最后一个字符错误
  }

  String _buildRealtimeHint({required Word word, required String userInput}) {
    final targetWord = word.word;
    final userInputLower = userInput.toLowerCase();
    final targetWordLower = targetWord.toLowerCase();
    
    // 找到正确输入的最长前缀
    int correctPrefixLength = 0;
    for (int i = 0; i < userInput.length && i < targetWord.length; i++) {
      if (userInputLower[i] == targetWordLower[i]) {
        correctPrefixLength++;
      } else {
        break;
      }
    }
    
    final correctPrefix = targetWord.substring(0, correctPrefixLength);
    final remainingPart = targetWord.substring(correctPrefixLength);
    
    return '$correctPrefix$remainingPart ${word.meaning}';
  }

  void _scheduleInputAction(String userInput, String targetWord) {
    _inputActionTimer?.cancel();
    
    _inputActionTimer = Timer(const Duration(seconds: 1), () {
      if (_onInputAction != null) {
        if (userInput.length < 7) {
          // 小于7个字母，清空输入框
          _onInputAction!('clear');
        } else {
          // 大于等于7个字母，回退到上一个正确字母处
          final correctPrefix = _getCorrectPrefix(userInput, targetWord);
          _onInputAction!(correctPrefix);
        }
      }
    });
  }

  String _getCorrectPrefix(String userInput, String targetWord) {
    final userInputLower = userInput.toLowerCase();
    final targetWordLower = targetWord.toLowerCase();
    
    int correctLength = 0;
    for (int i = 0; i < userInput.length && i < targetWord.length; i++) {
      if (userInputLower[i] == targetWordLower[i]) {
        correctLength++;
      } else {
        break;
      }
    }
    
    return targetWord.substring(0, correctLength);
  }

  void _scheduleHintFadeOut() {
    _hintFadeTimer?.cancel();
    _hintVisible = true;
    notifyListeners();
    
    _hintFadeTimer = Timer(const Duration(seconds: 2), () {
      _hintVisible = false;
      notifyListeners();
    });
  }

  void _addWrong(Word word) {
    if (word.inWrongList) return;
    word.inWrongList = true;
    _wrongWords.add(word);
  }

  void _advanceWithinPhaseOrTransition() {
    _cancelTimer();
    _wordVisible = true;

    if (_index < _currentList.length - 1) {
      _index += 1;
      _hintText = '';
      notifyListeners();
      _speakCurrent();
      _scheduleAutoAdvanceIfNeeded();
      if (_phase == Phase.recall) {
        _enterRecallForCurrent();
      }
      return;
    }

    _transitionPhase();
  }

  void _transitionPhase() {
    _cancelTimer();
    _index = 0;
    _hintText = '';
    _wordVisible = true;

    switch (_phase) {
      case Phase.preview:
        _phase = Phase.spellingInput;
        break;
      case Phase.spellingInput:
        _phase = Phase.recall;
        break;
      case Phase.recall:
        _phase = _wrongWords.isNotEmpty ? Phase.wrongReview : Phase.blindTest;
        _phaseLoopCount = 0;
        if (_phase == Phase.wrongReview) {
          _currentList = List<Word>.from(_wrongWords);
        }
        break;
      case Phase.wrongReview:
        _phase = Phase.blindTest;
        _currentList = List<Word>.from(_allWords.take(10));
        break;
      case Phase.blindTest:
        if (_wrongWords.isNotEmpty && _phaseLoopCount < 1) {
          _phaseLoopCount += 1;
          _phase = Phase.wrongReview;
          _currentList = List<Word>.from(_wrongWords);
        } else {
          _phase = Phase.completion;
        }
        break;
      case Phase.completion:
        break;
    }

    notifyListeners();
    if (_phase == Phase.recall) {
      _enterRecallForCurrent();
    }
    _speakCurrent();
    _scheduleAutoAdvanceIfNeeded();
  }

  void _scheduleAutoAdvanceIfNeeded() {
    if (_phase != Phase.preview) return;
    final delay = Duration(milliseconds: (1500 + 200 * currentWord.length));
    _timer = Timer(delay, _advanceWithinPhaseOrTransition);
  }

  void _enterRecallForCurrent() {
    _cancelTimer();
    _wordVisible = true;
    notifyListeners();

    final delay = Duration(milliseconds: (1500 + 200 * currentWord.length));
    _timer = Timer(delay, () {
      _wordVisible = false;
      notifyListeners();
      _speakCurrent();
    });
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _speakCurrent() {
    if (_phase == Phase.preview ||
        _phase == Phase.recall ||
        _phase == Phase.blindTest ||
        _phase == Phase.spellingInput) {
      unawaited(_ttsService.speak(currentWord.word));
    }
  }

  static String _buildHint({required Word word, required int errorCount, required Phase phase}) {
    if (phase == Phase.spellingInput) {
      return word.word;
    }

    if (errorCount <= 0) return '';

    final root2 = word.word.length >= 2 ? word.word.substring(0, 2) : word.word;
    final root4 = word.word.length >= 4 ? word.word.substring(0, 4) : word.word;

    if (phase == Phase.recall) {
      if (errorCount == 1) {
        return '${root2}___  ${word.meaning}';
      }

      if (errorCount == 2) {
        return '${root4}___  ${word.meaning}';
      }

      return word.word;
    }

    if (errorCount == 1) {
      return '${root2}___  ${word.phonetic}';
    }

    if (errorCount == 2) {
      return '${root4}___  ${word.meaning}  ${word.phonetic}';
    }

    return word.word;
  }
}

List<Word> _buildInitialWords() {
  final rows = <Map<String, String>>[
    {'group': '1', 'index': '1', 'word': 'travel', 'ipa': '/ˈtrævəl/', 'chinese': '旅行'},
    {'group': '1', 'index': '2', 'word': 'trip', 'ipa': '/trɪp/', 'chinese': '行程'},
    {'group': '1', 'index': '3', 'word': 'ticket', 'ipa': '/ˈtɪkɪt/', 'chinese': '票'},
    {'group': '1', 'index': '4', 'word': 'bus', 'ipa': '/bʌs/', 'chinese': '公交车'},
    {'group': '1', 'index': '5', 'word': 'taxi', 'ipa': '/ˈtæksi/', 'chinese': '出租车'},
    {'group': '1', 'index': '6', 'word': 'train', 'ipa': '/treɪn/', 'chinese': '火车'},
    {'group': '1', 'index': '7', 'word': 'plane', 'ipa': '/pleɪn/', 'chinese': '飞机'},
    {'group': '1', 'index': '8', 'word': 'car', 'ipa': '/kɑːr/', 'chinese': '汽车'},
    {'group': '1', 'index': '9', 'word': 'road', 'ipa': '/roʊd/', 'chinese': '道路'},
    {'group': '1', 'index': '10', 'word': 'map', 'ipa': '/mæp/', 'chinese': '地图'},

    {'group': '2', 'index': '11', 'word': 'airport', 'ipa': '/ˈerpɔːrt/', 'chinese': '机场'},
    {'group': '2', 'index': '12', 'word': 'station', 'ipa': '/ˈsteɪʃən/', 'chinese': '车站'},
    {'group': '2', 'index': '13', 'word': 'stop', 'ipa': '/stɑːp/', 'chinese': '站点'},
    {'group': '2', 'index': '14', 'word': 'gate', 'ipa': '/ɡeɪt/', 'chinese': '登机口'},
    {'group': '2', 'index': '15', 'word': 'exit', 'ipa': '/ˈeksɪt/', 'chinese': '出口'},
    {'group': '2', 'index': '16', 'word': 'entrance', 'ipa': '/ˈentrəns/', 'chinese': '入口'},
    {'group': '2', 'index': '17', 'word': 'platform', 'ipa': '/ˈplætfɔːrm/', 'chinese': '站台'},
    {'group': '2', 'index': '18', 'word': 'terminal', 'ipa': '/ˈtɜːrmɪnəl/', 'chinese': '航站楼'},
    {'group': '2', 'index': '19', 'word': 'counter', 'ipa': '/ˈkaʊntər/', 'chinese': '柜台'},
    {'group': '2', 'index': '20', 'word': 'office', 'ipa': '/ˈɔːfɪs/', 'chinese': '办公室'},

    {'group': '3', 'index': '21', 'word': 'go', 'ipa': '/ɡoʊ/', 'chinese': '去'},
    {'group': '3', 'index': '22', 'word': 'come', 'ipa': '/kʌm/', 'chinese': '来'},
    {'group': '3', 'index': '23', 'word': 'arrive', 'ipa': '/əˈraɪv/', 'chinese': '到达'},
    {'group': '3', 'index': '24', 'word': 'leave', 'ipa': '/liːv/', 'chinese': '离开'},
    {'group': '3', 'index': '25', 'word': 'wait', 'ipa': '/weɪt/', 'chinese': '等待'},
    {'group': '3', 'index': '26', 'word': 'stop', 'ipa': '/stɑːp/', 'chinese': '停止'},
    {'group': '3', 'index': '27', 'word': 'enter', 'ipa': '/ˈentər/', 'chinese': '进入'},
    {'group': '3', 'index': '28', 'word': 'exit', 'ipa': '/ˈeksɪt/', 'chinese': '离开'},
    {'group': '3', 'index': '29', 'word': 'check', 'ipa': '/tʃek/', 'chinese': '检查'},
    {'group': '3', 'index': '30', 'word': 'follow', 'ipa': '/ˈfɑːloʊ/', 'chinese': '跟随'},

    {'group': '4', 'index': '31', 'word': 'time', 'ipa': '/taɪm/', 'chinese': '时间'},
    {'group': '4', 'index': '32', 'word': 'today', 'ipa': '/təˈdeɪ/', 'chinese': '今天'},
    {'group': '4', 'index': '33', 'word': 'tomorrow', 'ipa': '/təˈmɑːroʊ/', 'chinese': '明天'},
    {'group': '4', 'index': '34', 'word': 'now', 'ipa': '/naʊ/', 'chinese': '现在'},
    {'group': '4', 'index': '35', 'word': 'early', 'ipa': '/ˈɜːrli/', 'chinese': '早'},
    {'group': '4', 'index': '36', 'word': 'late', 'ipa': '/leɪt/', 'chinese': '晚'},
    {'group': '4', 'index': '37', 'word': 'daily', 'ipa': '/ˈdeɪli/', 'chinese': '每天'},
    {'group': '4', 'index': '38', 'word': 'schedule', 'ipa': '/ˈskedʒuːl/', 'chinese': '时间表'},
    {'group': '4', 'index': '39', 'word': 'delay', 'ipa': '/dɪˈleɪ/', 'chinese': '延误'},
    {'group': '4', 'index': '40', 'word': 'cancel', 'ipa': '/ˈkænsəl/', 'chinese': '取消'},

    {'group': '5', 'index': '41', 'word': 'book', 'ipa': '/bʊk/', 'chinese': '预订'},
    {'group': '5', 'index': '42', 'word': 'booking', 'ipa': '/ˈbʊkɪŋ/', 'chinese': '预订'},
    {'group': '5', 'index': '43', 'word': 'reservation', 'ipa': '/ˌrezərˈveɪʃən/', 'chinese': '预约'},
    {'group': '5', 'index': '44', 'word': 'confirm', 'ipa': '/kənˈfɜːrm/', 'chinese': '确认'},
    {'group': '5', 'index': '45', 'word': 'check-in', 'ipa': '/ˈtʃek ɪn/', 'chinese': '办理登机'},
    {'group': '5', 'index': '46', 'word': 'check-out', 'ipa': '/ˈtʃek aʊt/', 'chinese': '退房'},
    {'group': '5', 'index': '47', 'word': 'boarding', 'ipa': '/ˈbɔːrdɪŋ/', 'chinese': '登机'},
    {'group': '5', 'index': '48', 'word': 'seat', 'ipa': '/siːt/', 'chinese': '座位'},
    {'group': '5', 'index': '49', 'word': 'number', 'ipa': '/ˈnʌmbər/', 'chinese': '编号'},
    {'group': '5', 'index': '50', 'word': 'class', 'ipa': '/klæs/', 'chinese': '等级'},

    {'group': '6', 'index': '51', 'word': 'bag', 'ipa': '/bæɡ/', 'chinese': '包'},
    {'group': '6', 'index': '52', 'word': 'luggage', 'ipa': '/ˈlʌɡɪdʒ/', 'chinese': '行李'},
    {'group': '6', 'index': '53', 'word': 'baggage', 'ipa': '/ˈbæɡɪdʒ/', 'chinese': '行李'},
    {'group': '6', 'index': '54', 'word': 'suitcase', 'ipa': '/ˈsuːtkeɪs/', 'chinese': '行李箱'},
    {'group': '6', 'index': '55', 'word': 'backpack', 'ipa': '/ˈbækpæk/', 'chinese': '背包'},
    {'group': '6', 'index': '56', 'word': 'carry-on', 'ipa': '/ˈkæri ɑːn/', 'chinese': '随身行李'},
    {'group': '6', 'index': '57', 'word': 'checked baggage', 'ipa': "/tʃekt ˈbæɡɪdʒ/", 'chinese': '托运行李'},
    {'group': '6', 'index': '58', 'word': 'lost', 'ipa': '/lɔːst/', 'chinese': '丢失的'},
    {'group': '6', 'index': '59', 'word': 'heavy', 'ipa': '/ˈhevi/', 'chinese': '重的'},
    {'group': '6', 'index': '60', 'word': 'light', 'ipa': '/laɪt/', 'chinese': '轻的'},
  ];

  return rows
      .map(
        (r) => Word(
          id: '${r['group']}-${r['index']}',
          word: r['word']!,
          phonetic: r['ipa']!,
          meaning: r['chinese']!,
        ),
      )
      .toList();
}
