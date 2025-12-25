import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../phase.dart';
import '../wordloop_controller.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final TextEditingController _textController = TextEditingController();
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
              style: controller.phase == Phase.recall && controller.errorPosition >= 0
                  ? Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.red,
                    )
                  : Theme.of(context).textTheme.titleMedium,
              cursorColor: Theme.of(context).colorScheme.primary,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: '输入拼写',
                errorText: controller.phase == Phase.recall && controller.errorPosition >= 0
                    ? '错误位置: ${controller.errorPosition + 1}'
                    : null,
                errorStyle: const TextStyle(color: Colors.red),
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

  Widget _buildErrorHighlight(WordLoopController controller) {
    final text = _textController.text;
    final errorPosition = controller.errorPosition;
    
    // 添加边界检查
    if (errorPosition < 0 || errorPosition >= text.length || text.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return RichText(
      text: TextSpan(
        children: [
          // 正确的字母
          if (errorPosition > 0)
            TextSpan(
              text: text.substring(0, errorPosition),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.transparent,
              ),
            ),
          // 错误的字母
          TextSpan(
            text: text[errorPosition],
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Colors.red,
              decoration: TextDecoration.underline,
              decorationColor: Colors.red,
            ),
          ),
          // 剩余的字母（如果有）
          if (errorPosition + 1 < text.length)
            TextSpan(
              text: text.substring(errorPosition + 1),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.transparent,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRichTextRenderer(Widget child, WordLoopController controller) {
    final text = _textController.text;
    final errorPosition = controller.errorPosition;
    
    if (controller.phase != Phase.recall || errorPosition < 0 || errorPosition >= text.length) {
      return child;
    }
    
    return RichText(
      text: TextSpan(
        children: [
          // 正确的字母
          TextSpan(
            text: text.substring(0, errorPosition),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          // 错误的字母
          TextSpan(
            text: text[errorPosition],
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Colors.red,
            ),
          ),
          // 剩余的字母（如果有）
          if (errorPosition + 1 < text.length)
            TextSpan(
              text: text.substring(errorPosition + 1),
              style: Theme.of(context).textTheme.titleMedium,
            ),
        ],
      ),
    );
  }

  Color _getTextColor(int errorPosition) {
    // 如果有错误位置，整个文本显示红色
    return errorPosition >= 0 ? Colors.red : Theme.of(context).textTheme.titleMedium?.color ?? Colors.black;
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
            AnimatedOpacity(
              duration: const Duration(milliseconds: 250),
              opacity: controller.wordVisible && controller.phase != Phase.blindTest ? 1 : 0,
              child: Text(
                word.word,
                style: Theme.of(context).textTheme.displaySmall,
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
            if (controller.phase != Phase.preview)
              _buildCustomTextField(controller),
            const SizedBox(height: 12),
            SizedBox(
              height: 40,
              child: Center(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 500),
                  opacity: controller.hintVisible ? 1.0 : 0.0,
                  child: controller.phase == Phase.recall && controller.hintText.isNotEmpty
                      ? _buildRichHint(controller.hintText, controller.currentWord.word)
                      : Text(
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
