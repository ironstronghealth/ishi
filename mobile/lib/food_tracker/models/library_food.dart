import 'food_item.dart';

/// A food the user has a relationship with: logged before, starred,
/// created by hand, or scanned. Backs the Recent / Frequent / Favourites /
/// My Foods lists and the local barcode lookup.
class LibraryFood {
  final FoodItem food;
  final bool isFavorite;

  /// True when the user typed in the nutrition facts themselves.
  final bool isCustom;

  /// Package barcode this food was scanned from or saved against.
  final String? barcode;

  final int useCount;
  final DateTime? lastUsedAt;

  const LibraryFood({
    required this.food,
    this.isFavorite = false,
    this.isCustom = false,
    this.barcode,
    this.useCount = 0,
    this.lastUsedAt,
  });

  LibraryFood copyWith({
    FoodItem? food,
    bool? isFavorite,
    bool? isCustom,
    String? barcode,
    int? useCount,
    DateTime? lastUsedAt,
  }) =>
      LibraryFood(
        food: food ?? this.food,
        isFavorite: isFavorite ?? this.isFavorite,
        isCustom: isCustom ?? this.isCustom,
        barcode: barcode ?? this.barcode,
        useCount: useCount ?? this.useCount,
        lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      );

  /// Whether anything still justifies keeping this row.
  bool get isWorthKeeping =>
      isFavorite || isCustom || barcode != null || useCount > 0;
}
