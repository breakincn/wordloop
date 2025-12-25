enum Phase {
  preview,
  spellingInput,
  recall,
  wrongReview,
  blindTest,
  completion,
}

extension PhaseLabel on Phase {
  String get label {
    switch (this) {
      case Phase.preview:
        return '阶段0 预览';
      case Phase.spellingInput:
        return '阶段1 拼写输入';
      case Phase.recall:
        return '阶段2 回忆';
      case Phase.wrongReview:
        return '阶段3 错词复习';
      case Phase.blindTest:
        return '阶段4 盲打';
      case Phase.completion:
        return '阶段5 完成';
    }
  }
}
