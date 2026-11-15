import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishi_mobile/food_tracker/models/food_item.dart';
import 'package:ishi_mobile/food_tracker/screens/serving_size_screen.dart';

void main() {
  // Non-numeric id, so the screen does not try to fetch USDA portions.
  const food = FoodItem(
    id: 'custom_test',
    name: 'Granola',
    calories: 400,
    protein: 10,
    carbs: 60,
    fat: 15,
    iron: 4,
    servingSize: 100,
    portions: [FoodPortion(label: '1 cup', grams: 50)],
  );

  Future<void> pumpPicker(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: ServingSizeScreen(food: food, pickerMode: true),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('starts at one natural portion and previews its nutrition',
      (tester) async {
    await pumpPicker(tester);

    expect(find.text('cup (50 g)'), findsOneWidget);
    expect(find.text('= 50 g'), findsOneWidget);
    expect(find.text('200.0 kcal'), findsOneWidget);
    expect(find.text('2.0 mg'), findsOneWidget);
  });

  testWidgets('stepping and switching to grams keeps amounts consistent',
      (tester) async {
    await pumpPicker(tester);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(find.text('= 75 g'), findsOneWidget); // 1.5 cups

    await tester.tap(find.text('cup (50 g)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('g').last);
    await tester.pumpAndSettle();

    expect(find.text('75'), findsOneWidget); // same food, now in grams
    expect(find.text('= 75 g'), findsOneWidget);
    expect(find.text('300.0 kcal'), findsOneWidget);
  });

  testWidgets('rejects an empty amount', (tester) async {
    await pumpPicker(tester);

    await tester.enterText(find.byType(TextField), '');
    await tester.pump();

    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Add to Meal'),
    );
    expect(button.onPressed, isNull);
  });
}
