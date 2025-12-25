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
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
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
              TextField(
                controller: _textController,
                focusNode: _focusNode,
                textInputAction: TextInputAction.done,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: const [],
              onSubmitted: (value) async {
                await controller.submit(value);
                _textController.clear();
                _focusNode.requestFocus();
              },
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '输入拼写',
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 40,
              child: Center(
                child: Text(
                  controller.hintText,
                  style: Theme.of(context).textTheme.titleMedium,
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
}
