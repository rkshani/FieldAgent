class AlreadyAddedItem {
  final String? bookId;
  final String? alreadyInOrder;

  AlreadyAddedItem({this.bookId, this.alreadyInOrder});

  factory AlreadyAddedItem.fromJson(Map<String, dynamic> json) {
    return AlreadyAddedItem(
      bookId: json['bookid']?.toString(),
      alreadyInOrder: json['already_in_order']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {'bookid': bookId, 'already_in_order': alreadyInOrder};
  }

  bool get isInOrder =>
      alreadyInOrder == '1' || alreadyInOrder?.toLowerCase() == 'yes';
}
