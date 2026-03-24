class DictionaryItem {
  final int? id;
  final String raw;
  final String pinyin;
  final String abbreviation;

  DictionaryItem({
    this.id,
    required this.raw,
    required this.pinyin,
    required this.abbreviation,
  });

  factory DictionaryItem.fromMap(Map<String, dynamic> map) {
    return DictionaryItem(
      id: map['id'] as int?,
      raw: map['raw'] as String? ?? '',
      pinyin: map['pinyin'] as String? ?? '',
      abbreviation: map['abbreviation'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'raw': raw,
      'pinyin': pinyin,
      'abbreviation': abbreviation,
    };
  }

  bool matches(String query) {
    final lowerQuery = query.toLowerCase();
    return raw.toLowerCase().contains(lowerQuery) ||
           pinyin.toLowerCase().contains(lowerQuery) ||
           abbreviation.toLowerCase().contains(lowerQuery);
  }

  @override
  String toString() => raw;
}