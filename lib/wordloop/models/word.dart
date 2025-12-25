class Word {
  Word({
    required this.id,
    required this.word,
    required this.phonetic,
    required this.meaning,
    this.stage = 0,
    this.errorCount = 0,
    this.inWrongList = false,
    this.priority = 0,
    DateTime? lastAttempt,
    this.attemptCount = 0,
    this.isKeyWord = false,
  }) : lastAttempt = lastAttempt ?? DateTime.fromMillisecondsSinceEpoch(0);

  final String id;
  final String word;
  final String phonetic;
  final String meaning;

  int stage;
  int errorCount;
  bool inWrongList;
  int priority;
  DateTime lastAttempt;
  int attemptCount;
  bool isKeyWord;

  int get length => word.length;
}
