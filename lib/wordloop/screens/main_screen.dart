import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:math';

import '../phase.dart';
import '../wordloop_controller.dart';

class HighlightTextEditingController extends TextEditingController {
  Phase phase = Phase.preview;
  String targetWordLower = '';

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    final text = value.text;
    if (phase != Phase.recall || text.isEmpty || targetWordLower.isEmpty) {
      return TextSpan(style: style, text: text);
    }

    final baseStyle = style ?? const TextStyle();
    final children = <InlineSpan>[];
    for (int i = 0; i < text.length; i++) {
      final ch = text[i];
      final isWrong = i >= targetWordLower.length || ch.toLowerCase() != targetWordLower[i];
      children.add(
        TextSpan(
          text: ch,
          style: isWrong ? baseStyle.copyWith(color: Colors.red) : null,
        ),
      );
    }

    return TextSpan(style: style, children: children);
  }
}

class _LetterToken {
  final String id;
  final String ch;

  const _LetterToken({required this.id, required this.ch});
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final HighlightTextEditingController _textController = HighlightTextEditingController();

  final Random _random = Random();
  String _letterPoolForWord = '';
  List<_LetterToken> _availableLetters = <_LetterToken>[];
  List<_LetterToken> _selectedLetters = <_LetterToken>[];

  String _spellingStateForWord = '';
  List<_LetterToken?> _spellingCorrectTokens = <_LetterToken?>[];
  List<bool> _spellingWrongAtIndex = <bool>[];

  String _blindStateForWord = '';
  List<_LetterToken?> _blindCorrectTokens = <_LetterToken?>[];
  List<bool> _blindWrongAtIndex = <bool>[];
  int _blindWrongIndex = -1;
  String _blindWrongChar = '';
  Timer? _blindWrongHideTimer;

  bool _lastHintVisible = false;
  bool _recallHadErrorWhileHintVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WordLoopController>().start();
      context.read<WordLoopController>().setInputActionCallback(_handleInputAction);
    });
  }

  @override
  void dispose() {
    _blindWrongHideTimer?.cancel();
    _textController.dispose();
    super.dispose();
  }

  void _ensureLetterPool(String targetWord) {
    if (_letterPoolForWord == targetWord) return;
    _letterPoolForWord = targetWord;
    _availableLetters = List<_LetterToken>.generate(
      targetWord.length,
      (i) => _LetterToken(id: '${targetWord}_$i', ch: targetWord[i]),
    );
    _availableLetters.shuffle(_random);
    _selectedLetters = <_LetterToken>[];
    _textController.text = '';
  }

  void _ensureSpellingState(String targetWord) {
    if (_spellingStateForWord == targetWord) return;
    _spellingStateForWord = targetWord;
    _spellingCorrectTokens = List<_LetterToken?>.filled(targetWord.length, null);
    _spellingWrongAtIndex = List<bool>.filled(targetWord.length, false);
    _ensureLetterPool(targetWord);
  }

  void _ensureBlindState(String targetWord) {
    if (_blindStateForWord == targetWord) return;
    _blindStateForWord = targetWord;
    _blindCorrectTokens = List<_LetterToken?>.filled(targetWord.length, null);
    _blindWrongAtIndex = List<bool>.filled(targetWord.length, false);
    _ensureLetterPool(targetWord);
  }

  int _spellingNextIndex() {
    for (int i = 0; i < _spellingCorrectTokens.length; i++) {
      if (_spellingCorrectTokens[i] == null) return i;
    }
    return _spellingCorrectTokens.length;
  }

  int _blindNextIndex() {
    for (int i = 0; i < _blindCorrectTokens.length; i++) {
      if (_blindCorrectTokens[i] == null) return i;
    }
    return _blindCorrectTokens.length;
  }

  void _syncTextFromSpellingCorrect() {
    final buffer = StringBuffer();
    for (final t in _spellingCorrectTokens) {
      if (t == null) break;
      buffer.write(t.ch);
    }
    _textController.text = buffer.toString();
  }

  void _syncTextFromBlindCorrect() {
    final buffer = StringBuffer();
    for (final t in _blindCorrectTokens) {
      if (t == null) break;
      buffer.write(t.ch);
    }
    _textController.text = buffer.toString();
  }

  Widget _buildBlindWordStatusText({required String targetWord, required TextStyle? style}) {
    _ensureBlindState(targetWord);
    final baseStyle = style ?? const TextStyle();
    final nextIdx = _blindNextIndex();

    final spans = <InlineSpan>[];
    for (int i = 0; i < targetWord.length; i++) {
      if (_blindCorrectTokens.length > i && _blindCorrectTokens[i] != null) {
        spans.add(
          TextSpan(
            text: _blindCorrectTokens[i]!.ch,
            style: baseStyle.copyWith(color: Colors.green, fontWeight: FontWeight.bold),
          ),
        );
        continue;
      }

      if (i == nextIdx && _blindWrongIndex == nextIdx && _blindWrongChar.isNotEmpty) {
        spans.add(
          TextSpan(
            text: _blindWrongChar,
            style: baseStyle.copyWith(color: Colors.red, fontWeight: FontWeight.bold),
          ),
        );
        continue;
      }

      spans.add(
        TextSpan(
          text: ' ',
          style: baseStyle.copyWith(color: Colors.transparent, fontWeight: FontWeight.bold),
        ),
      );
    }

    return RichText(text: TextSpan(children: spans));
  }

  void _resetLetterPool(String targetWord) {
    _letterPoolForWord = '';
    _ensureLetterPool(targetWord);
  }

  void _applyInputToTokens({required String targetWord, required String input}) {
    _resetLetterPool(targetWord);
    final buffer = StringBuffer();
    for (int i = 0; i < input.length; i++) {
      final ch = input[i];
      final idx = _availableLetters.indexWhere((t) => t.ch == ch);
      if (idx < 0) break;
      final token = _availableLetters.removeAt(idx);
      _selectedLetters.add(token);
      buffer.write(ch);
    }
    _textController.text = buffer.toString();
  }

  Future<void> _submitSpelling(WordLoopController controller) async {
    final input = _textController.text;
    if (input.trim().isEmpty) return;
    await controller.submit(input);

    if (!mounted) return;
    setState(() {
      _letterPoolForWord = '';
      _availableLetters = <_LetterToken>[];
      _selectedLetters = <_LetterToken>[];
      _textController.clear();
    });
  }

  void _onPickLetter(WordLoopController controller, _LetterToken token) {
    if (controller.phase == Phase.spellingInput) {
      final targetWord = controller.currentWord.word;
      _ensureSpellingState(targetWord);
      final idx = _spellingNextIndex();
      if (idx >= targetWord.length) return;

      final isCorrect = token.ch.toLowerCase() == targetWord[idx].toLowerCase();
      setState(() {
        if (isCorrect) {
          _spellingCorrectTokens[idx] = token;
          _spellingWrongAtIndex[idx] = false;
          _availableLetters.removeWhere((t) => t.id == token.id);
          _selectedLetters.add(token);
          _syncTextFromSpellingCorrect();
        } else {
          _spellingWrongAtIndex[idx] = true;
        }
      });

      if (_spellingNextIndex() >= targetWord.length) {
        _submitSpelling(controller);
      }
      return;
    }

    if (controller.phase == Phase.blindTest) {
      final targetWord = controller.currentWord.word;
      _ensureBlindState(targetWord);
      final idx = _blindNextIndex();
      if (idx >= targetWord.length) return;

      final isCorrect = token.ch.toLowerCase() == targetWord[idx].toLowerCase();
      setState(() {
        if (isCorrect) {
          _blindCorrectTokens[idx] = token;
          _blindWrongAtIndex[idx] = false;
          if (_blindWrongIndex == idx) {
            _blindWrongIndex = -1;
            _blindWrongChar = '';
          }
          _blindWrongHideTimer?.cancel();
          _availableLetters.removeWhere((t) => t.id == token.id);
          _selectedLetters.add(token);
          _syncTextFromBlindCorrect();
        } else {
          _blindWrongAtIndex[idx] = true;
          _blindWrongIndex = idx;
          _blindWrongChar = token.ch;
          _blindWrongHideTimer?.cancel();
          _blindWrongHideTimer = Timer(const Duration(seconds: 1), () {
            if (!mounted) return;
            final c = context.read<WordLoopController>();
            if (c.phase != Phase.blindTest) return;
            setState(() {
              if (_blindWrongIndex == idx) {
                _blindWrongIndex = -1;
                _blindWrongChar = '';
                if (_blindWrongAtIndex.length > idx) {
                  _blindWrongAtIndex[idx] = false;
                }
              }
            });
          });
        }
      });

      controller.checkInputRealtime(_textController.text);
      return;
    }

    setState(() {
      _availableLetters.removeWhere((t) => t.id == token.id);
      _selectedLetters.add(token);
      _textController.text = '${_textController.text}${token.ch}';
    });

    if (controller.phase == Phase.recall || controller.phase == Phase.blindTest) {
      controller.checkInputRealtime(_textController.text);
    }

    if (controller.phase != Phase.blindTest && _textController.text.length >= controller.currentWord.word.length) {
      _submitSpelling(controller);
    }
  }

  void _onBackspace() {
    final controller = context.read<WordLoopController>();
    if (controller.phase == Phase.spellingInput) {
      final targetWord = controller.currentWord.word;
      _ensureSpellingState(targetWord);
      final nextIdx = _spellingNextIndex();
      final idx = (nextIdx - 1).clamp(0, targetWord.length - 1);

      setState(() {
        if (_spellingCorrectTokens[idx] != null) {
          final token = _spellingCorrectTokens[idx]!;
          _spellingCorrectTokens[idx] = null;
          _spellingWrongAtIndex[idx] = false;
          _selectedLetters.removeWhere((t) => t.id == token.id);
          _availableLetters.add(token);
          _availableLetters.shuffle(_random);
        } else {
          _spellingWrongAtIndex[idx] = false;
        }
        _syncTextFromSpellingCorrect();
      });
      return;
    }

    if (controller.phase == Phase.blindTest) {
      final targetWord = controller.currentWord.word;
      _ensureBlindState(targetWord);
      final nextIdx = _blindNextIndex();
      if (_blindWrongIndex == nextIdx && _blindWrongChar.isNotEmpty) {
        setState(() {
          _blindWrongAtIndex[nextIdx] = false;
          _blindWrongIndex = -1;
          _blindWrongChar = '';
        });
        return;
      }

      final idx = (nextIdx - 1).clamp(0, targetWord.length - 1);

      setState(() {
        if (_blindCorrectTokens[idx] != null) {
          final token = _blindCorrectTokens[idx]!;
          _blindCorrectTokens[idx] = null;
          _blindWrongAtIndex[idx] = false;
          if (_blindWrongIndex == idx) {
            _blindWrongIndex = -1;
            _blindWrongChar = '';
          }
          _selectedLetters.removeWhere((t) => t.id == token.id);
          _availableLetters.add(token);
          _availableLetters.shuffle(_random);
        } else {
          _blindWrongAtIndex[idx] = false;
        }
        _syncTextFromBlindCorrect();
      });

      controller.checkInputRealtime(_textController.text);
      return;
    }

    if (_selectedLetters.isEmpty) return;
    setState(() {
      final last = _selectedLetters.removeLast();
      _availableLetters.add(last);
      if (_textController.text.isNotEmpty) {
        _textController.text = _textController.text.substring(0, _textController.text.length - 1);
      }
    });
  }

  void _onClearSpelling() {
    final controller = context.read<WordLoopController>();
    if (controller.phase == Phase.spellingInput) {
      final targetWord = controller.currentWord.word;
      _ensureSpellingState(targetWord);
      setState(() {
        _spellingCorrectTokens = List<_LetterToken?>.filled(targetWord.length, null);
        _spellingWrongAtIndex = List<bool>.filled(targetWord.length, false);
        _availableLetters = List<_LetterToken>.generate(
          targetWord.length,
          (i) => _LetterToken(id: '${targetWord}_$i', ch: targetWord[i]),
        );
        _availableLetters.shuffle(_random);
        _selectedLetters.clear();
        _textController.clear();
      });
      return;
    }

    if (controller.phase == Phase.blindTest) {
      final targetWord = controller.currentWord.word;
      _ensureBlindState(targetWord);
      setState(() {
        _blindCorrectTokens = List<_LetterToken?>.filled(targetWord.length, null);
        _blindWrongAtIndex = List<bool>.filled(targetWord.length, false);
        _blindWrongIndex = -1;
        _blindWrongChar = '';
        _availableLetters = List<_LetterToken>.generate(
          targetWord.length,
          (i) => _LetterToken(id: '${targetWord}_$i', ch: targetWord[i]),
        );
        _availableLetters.shuffle(_random);
        _selectedLetters.clear();
        _textController.clear();
      });

      controller.checkInputRealtime(_textController.text);
      return;
    }

    if (_selectedLetters.isEmpty) return;
    setState(() {
      _availableLetters.addAll(_selectedLetters);
      _selectedLetters.clear();
      _availableLetters.shuffle(_random);
      _textController.clear();
    });
  }

  Widget _buildSpellingWordStatusText({required String targetWord, required TextStyle? style}) {
    _ensureSpellingState(targetWord);
    final baseStyle = style ?? const TextStyle();
    final spans = <InlineSpan>[];
    for (int i = 0; i < targetWord.length; i++) {
      Color? color;
      FontWeight? weight;
      if (_spellingCorrectTokens.length > i && _spellingCorrectTokens[i] != null) {
        color = Colors.green;
        weight = FontWeight.bold;
      } else if (_spellingWrongAtIndex.length > i && _spellingWrongAtIndex[i]) {
        color = Colors.red;
        weight = FontWeight.bold;
      }
      spans.add(
        TextSpan(
          text: targetWord[i],
          style: baseStyle.copyWith(color: color, fontWeight: weight),
        ),
      );
    }
    return RichText(text: TextSpan(children: spans));
  }

  Widget _buildRecallHiddenWordProgress(WordLoopController controller) {
    final targetWord = controller.currentWord.word;
    final input = _textController.text.trim();
    if (input.isEmpty) {
      return const SizedBox.shrink();
    }

    final targetLower = targetWord.toLowerCase();
    final inputLower = input.toLowerCase();
    if (!targetLower.startsWith(inputLower)) {
      return const SizedBox.shrink();
    }

    final baseStyle = Theme.of(context).textTheme.displaySmall;
    final greenPrefix = targetWord.substring(0, input.length.clamp(0, targetWord.length));
    final rest = input.length < targetWord.length ? targetWord.substring(input.length) : '';

    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: greenPrefix,
            style: baseStyle?.copyWith(
              color: Colors.green,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (rest.isNotEmpty)
            TextSpan(
              text: rest,
              style: baseStyle?.copyWith(
                color: Colors.transparent,
              ),
            ),
        ],
      ),
    );
  }

  void _handleInputAction(String action) {
    final controller = context.read<WordLoopController>();
    final phase = controller.phase;
    if (phase == Phase.recall || phase == Phase.blindTest) {
      if (phase == Phase.recall && controller.hintVisible && controller.errorPosition >= 0) {
        return;
      }
      setState(() {
        final targetWord = controller.currentWord.word;
        if (phase == Phase.blindTest) {
          _ensureBlindState(targetWord);
          if (action == 'clear') {
            _blindCorrectTokens = List<_LetterToken?>.filled(targetWord.length, null);
            _blindWrongAtIndex = List<bool>.filled(targetWord.length, false);
            _blindWrongIndex = -1;
            _blindWrongChar = '';
            _availableLetters = List<_LetterToken>.generate(
              targetWord.length,
              (i) => _LetterToken(id: '${targetWord}_$i', ch: targetWord[i]),
            );
            _availableLetters.shuffle(_random);
            _selectedLetters.clear();
            _textController.clear();
          } else {
            _blindWrongIndex = -1;
            _blindWrongChar = '';
            _applyInputToTokens(targetWord: targetWord, input: action);
          }
        } else {
          if (action == 'clear') {
            _applyInputToTokens(targetWord: targetWord, input: '');
          } else {
            _applyInputToTokens(targetWord: targetWord, input: action);
          }
        }
      });

      if (phase == Phase.blindTest) {
        controller.checkInputRealtime(_textController.text);
      }
      return;
    }

    if (action == 'clear') {
      _textController.clear();
    } else {
      _textController.text = action;
      _textController.selection = TextSelection.fromPosition(
        TextPosition(offset: action.length),
      );
    }
    
  }

  Widget _buildSpellingInputPad(WordLoopController controller) {
    final targetWord = controller.currentWord.word;
    _ensureLetterPool(targetWord);

    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: _availableLetters
              .map(
                (t) => SizedBox(
                  width: 56,
                  height: 56,
                  child: FilledButton(
                    onPressed: () => _onPickLetter(controller, t),
                    style: FilledButton.styleFrom(
                      textStyle: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(t.ch),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 12),
        if (_availableLetters.isNotEmpty && _selectedLetters.isNotEmpty)
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _selectedLetters.isEmpty
                      ? null
                      : () {
                          _onBackspace();
                          if (controller.phase == Phase.recall || controller.phase == Phase.blindTest) {
                            controller.checkInputRealtime(_textController.text);
                          }
                        },
                  child: const Text('退格'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: _selectedLetters.isEmpty
                      ? null
                      : () {
                          _onClearSpelling();
                          if (controller.phase == Phase.recall || controller.phase == Phase.blindTest) {
                            controller.checkInputRealtime(_textController.text);
                          }
                        },
                  child: const Text('清空'),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildRecallHiddenWordHint(WordLoopController controller) {
    final targetWord = controller.currentWord.word;
    final input = _textController.text.trim();
    if (input.isEmpty) {
      return Text(
        targetWord,
        style: Theme.of(context).textTheme.displaySmall,
      );
    }

    int correctPrefixLength = 0;
    for (int i = 0; i < input.length && i < targetWord.length; i++) {
      if (input.toLowerCase()[i] == targetWord.toLowerCase()[i]) {
        correctPrefixLength++;
      } else {
        break;
      }
    }

    final correctPrefix = targetWord.substring(0, correctPrefixLength);
    final errorChar = correctPrefixLength < targetWord.length ? targetWord.substring(correctPrefixLength, correctPrefixLength + 1) : '';
    final remainingPart = correctPrefixLength + 1 < targetWord.length ? targetWord.substring(correctPrefixLength + 1) : '';

    final baseStyle = Theme.of(context).textTheme.displaySmall;
    final remainingColor = (controller.phase == Phase.recall || controller.phase == Phase.wrongReview) ? Colors.blue : Colors.green;
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: correctPrefix,
            style: baseStyle?.copyWith(
              color: Colors.green,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (errorChar.isNotEmpty)
            TextSpan(
              text: errorChar,
              style: baseStyle?.copyWith(
                color: Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          if (remainingPart.isNotEmpty)
            TextSpan(
              text: remainingPart,
              style: baseStyle?.copyWith(
                color: remainingColor,
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWordProgressText({required String targetWord, required TextStyle? style}) {
    final input = _textController.text.trim();
    if (input.isEmpty) {
      return Text(targetWord, style: style);
    }

    final targetLower = targetWord.toLowerCase();
    final inputLower = input.toLowerCase();

    int correctPrefixLength = 0;
    for (int i = 0; i < inputLower.length && i < targetLower.length; i++) {
      if (inputLower[i] == targetLower[i]) {
        correctPrefixLength++;
      } else {
        break;
      }
    }

    if (correctPrefixLength <= 0) {
      return Text(targetWord, style: style);
    }

    final prefix = targetWord.substring(0, correctPrefixLength);
    final rest = targetWord.substring(correctPrefixLength);

    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: prefix,
            style: style?.copyWith(
              color: Colors.green,
              fontWeight: FontWeight.bold,
            ),
          ),
          TextSpan(text: rest, style: style),
        ],
      ),
    );
  }

  Widget _buildBlindTypingProgressText({required String targetWord, required TextStyle? style}) {
    final input = _textController.text.trim();
    if (input.isEmpty) {
      return Text(targetWord, style: style?.copyWith(color: Colors.transparent));
    }

    final targetLower = targetWord.toLowerCase();
    final inputLower = input.toLowerCase();
    final baseStyle = style ?? const TextStyle();
    final children = <InlineSpan>[];

    for (int i = 0; i < targetWord.length; i++) {
      if (i >= inputLower.length) {
        children.add(
          TextSpan(
            text: targetWord[i],
            style: baseStyle.copyWith(color: Colors.transparent),
          ),
        );
        continue;
      }

      // 显示用户输入的字母，而不是目标字母
      final userInputChar = input[i];
      final isCorrect = i < targetLower.length && inputLower[i] == targetLower[i];
      children.add(
        TextSpan(
          text: userInputChar,
          style: baseStyle.copyWith(
            color: isCorrect ? Colors.green : Colors.black26,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    return RichText(text: TextSpan(children: children));
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<WordLoopController>();
    final word = controller.currentWord;

    // 阶段5完成页面使用独立布局
    if (controller.phase == Phase.completion) {
      return Scaffold(
        appBar: AppBar(
          title: Text('WordLoop  ${controller.phase.label}'),
          actions: [
            IconButton(
              onPressed: controller.playPronunciation,
              icon: const Icon(Icons.volume_up),
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '正确率 ${(controller.accuracy * 100).toStringAsFixed(1)}%  错词 ${controller.wrongWords.length}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.separated(
                  itemCount: controller.sessionWords.length,
                  separatorBuilder: (context, index) => const Divider(height: 16),
                  itemBuilder: (context, index) {
                    final w = controller.sessionWords[index];
                    final attempts = w.attemptCount;
                    final errors = w.errorCount;
                    final correct = (attempts - errors).clamp(0, attempts);
                    final rate = attempts == 0 ? 0.0 : (correct / attempts);

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 26,
                          child: Text(
                            '${index + 1}.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                w.word,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                w.meaning,
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${(rate * 100).toStringAsFixed(0)}% ($correct/$attempts)',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    controller.next();
                    _textController.clear();
                    _letterPoolForWord = '';
                    _availableLetters = <_LetterToken>[];
                    _selectedLetters = <_LetterToken>[];
                  },
                  child: const Text('重新开始'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 其他阶段的原有布局
    final hintVisible = controller.hintVisible;
    if (controller.phase == Phase.recall && hintVisible && controller.errorPosition >= 0) {
      _recallHadErrorWhileHintVisible = true;
    }
    if (_lastHintVisible && !hintVisible && controller.phase == Phase.recall && _recallHadErrorWhileHintVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final c = context.read<WordLoopController>();
        if (c.phase != Phase.recall) return;
        setState(() {
          _applyInputToTokens(targetWord: c.currentWord.word, input: '');
          _recallHadErrorWhileHintVisible = false;
        });
        c.checkInputRealtime('');
      });
    }
    _lastHintVisible = hintVisible;

    final showMeaning = controller.phase == Phase.blindTest ||
        controller.phase == Phase.preview ||
        controller.phase == Phase.spellingInput ||
        controller.phase == Phase.recall;

    return Scaffold(
      appBar: AppBar(
        title: Text('WordLoop  ${controller.phase.label}'),
        actions: [
          IconButton(
            onPressed: controller.playPronunciation,
            icon: const Icon(Icons.volume_up),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            LinearProgressIndicator(
              value: (controller.completedCount + 1) / controller.total,
            ),
            const SizedBox(height: 16),
            if (controller.phase != Phase.completion)
              Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 250),
                    opacity: controller.wordVisible && controller.phase != Phase.blindTest ? 1 : 0,
                    child: controller.phase == Phase.spellingInput
                        ? _buildSpellingWordStatusText(
                            targetWord: word.word,
                            style: Theme.of(context).textTheme.displaySmall,
                          )
                        : _buildWordProgressText(
                            targetWord: word.word,
                            style: Theme.of(context).textTheme.displaySmall,
                          ),
                  ),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 250),
                    opacity: (controller.phase == Phase.blindTest && !controller.blindWordHintVisible) ? 1 : 0,
                    child: _buildBlindWordStatusText(targetWord: word.word, style: Theme.of(context).textTheme.displaySmall),
                  ),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 500),
                    opacity: (controller.phase == Phase.blindTest && controller.blindWordHintVisible) ? 1 : 0,
                    child: Text(
                      word.word,
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 120),
                    opacity: (controller.phase == Phase.recall &&
                            !controller.wordVisible &&
                            controller.errorPosition < 0)
                        ? 1
                        : 0,
                    child: _buildRecallHiddenWordProgress(controller),
                  ),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 250),
                    opacity: (controller.phase == Phase.recall &&
                            !controller.wordVisible &&
                            controller.errorPosition >= 0 &&
                            controller.hintVisible)
                        ? 1
                        : 0,
                    child: _buildRecallHiddenWordHint(controller),
                  ),
                ],
              ),
            const SizedBox(height: 6),
            if (controller.phase != Phase.completion) ...[
              Text(
                '已提交次数 ${word.attemptCount}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                word.phonetic,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              if (showMeaning)
                Text(
                  word.meaning,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              const SizedBox(height: 12),
            ],
            if (controller.phase != Phase.completion) ...[
              if (controller.phase == Phase.wrongReview && word.word.isEmpty)
                const SizedBox.shrink()
              else if (controller.phase == Phase.spellingInput || controller.phase == Phase.recall || controller.phase == Phase.blindTest)
                _buildSpellingInputPad(controller)
              else if (controller.phase != Phase.preview)
                const SizedBox.shrink(),
              const SizedBox(height: 12),
              if (controller.phase != Phase.recall && controller.phase != Phase.blindTest)
                SizedBox(
                  height: 40,
                  child: Center(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 500),
                      opacity: controller.hintVisible ? 1.0 : 0.0,
                      child: controller.phase == Phase.wrongReview && controller.hintText.isNotEmpty
                          ? _buildRichHint(controller.hintText, controller.currentWord.word)
                          : Text(
                              controller.hintText,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                    ),
                  ),
                ),
            ],
            const Spacer(),
            if (controller.phase != Phase.completion)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: controller.skip,
                      child: const Text('跳过'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        controller.next();
                        _textController.clear();
                        _letterPoolForWord = '';
                        _availableLetters = <_LetterToken>[];
                        _selectedLetters = <_LetterToken>[];
                      },
                      child: Text(controller.phase == Phase.completion ? '重新开始' : '下一步'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRichHint(String hintText, String targetWord) {
    final parts = hintText.split(' ');
    final wordHint = parts[0];
    final meaning = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    
    // 找到用户输入的正确前缀长度
    final textController = _textController.text.trim();
    int correctPrefixLength = 0;
    for (int i = 0; i < textController.length && i < wordHint.length; i++) {
      if (textController.toLowerCase()[i] == wordHint.toLowerCase()[i]) {
        correctPrefixLength++;
      } else {
        break;
      }
    }
    
    final correctPrefix = wordHint.substring(0, correctPrefixLength);
    final remainingPart = wordHint.substring(correctPrefixLength);
    final remainingColor = context.read<WordLoopController>().phase == Phase.wrongReview ? Colors.blue : Colors.green;
    
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: correctPrefix,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          TextSpan(
            text: remainingPart,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: remainingColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (meaning.isNotEmpty)
            TextSpan(
              text: ' $meaning',
              style: Theme.of(context).textTheme.titleMedium,
            ),
        ],
      ),
    );
  }
}
