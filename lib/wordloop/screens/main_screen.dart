import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../phase.dart';
import '../wordloop_controller.dart';

class HighlightTextEditingController extends TextEditingController {
  int errorPosition = -1;
  Phase phase = Phase.preview;

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    final text = value.text;
    if (phase != Phase.recall || errorPosition < 0 || errorPosition >= text.length) {
      return TextSpan(style: style, text: text);
    }

    final before = errorPosition > 0 ? text.substring(0, errorPosition) : '';
    final wrong = text.substring(errorPosition, errorPosition + 1);
    final after = errorPosition + 1 < text.length ? text.substring(errorPosition + 1) : '';

    return TextSpan(
      style: style,
      children: [
        if (before.isNotEmpty) TextSpan(text: before),
        TextSpan(
          text: wrong,
          style: (style ?? const TextStyle()).copyWith(color: Colors.red),
        ),
        if (after.isNotEmpty) TextSpan(text: after),
      ],
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final HighlightTextEditingController _textController = HighlightTextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WordLoopController>().start();
      context.read<WordLoopController>().setInputActionCallback(_handleInputAction);
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Widget _buildCustomTextField(WordLoopController controller) {
    _textController.errorPosition = controller.errorPosition;
    _textController.phase = controller.phase;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '输入拼写',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _textController,
              focusNode: _focusNode,
              style: Theme.of(context).textTheme.titleMedium,
              cursorColor: Theme.of(context).colorScheme.primary,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: '输入拼写',
              ),
              onChanged: (value) {
                if (controller.phase == Phase.recall) {
                  controller.checkInputRealtime(value);
                }
                setState(() {});
              },
              onSubmitted: (value) async {
                await controller.submit(value);
                _textController.clear();
                _focusNode.requestFocus();
              },
              textCapitalization: TextCapitalization.none,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.done,
              autocorrect: false,
              enableSuggestions: false,
            ),
          ],
        ),
      ),
    );
  }

  void _handleInputAction(String action) {
    if (action == 'clear') {
      _textController.clear();
    } else {
      _textController.text = action;
      _textController.selection = TextSelection.fromPosition(
        TextPosition(offset: action.length),
      );
    }
    _focusNode.requestFocus();
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
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(text: correctPrefix, style: baseStyle),
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
                color: Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<WordLoopController>();
    final word = controller.currentWord;

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
            Stack(
              alignment: Alignment.center,
              children: [
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 250),
                  opacity: controller.wordVisible && controller.phase != Phase.blindTest ? 1 : 0,
                  child: Text(
                    word.word,
                    style: Theme.of(context).textTheme.displaySmall,
                  ),
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
            if (controller.phase != Phase.preview)
              _buildCustomTextField(controller),
            const SizedBox(height: 12),
            if (controller.phase != Phase.recall)
              SizedBox(
                height: 40,
                child: Center(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 500),
                    opacity: controller.hintVisible ? 1.0 : 0.0,
                    child: Text(
                      controller.hintText,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ),
              ),
            const Spacer(),
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
                      _focusNode.requestFocus();
                    },
                    child: Text(controller.phase == Phase.completion ? '重新开始' : '下一步'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (controller.phase == Phase.completion)
              Text(
                '正确率 ${(controller.accuracy * 100).toStringAsFixed(1)}%  错词 ${controller.wrongWords.length}',
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
              color: Colors.green,
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
