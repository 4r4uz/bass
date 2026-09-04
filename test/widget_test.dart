// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:bass/main.dart';
import 'package:bass/services/library_store.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Biblioteca vacía: el store sin inicializar no persiste nada (save no-op).
    await tester.pumpWidget(
      MyApp(library: LibraryStore(), initialTracks: const []),
    );
    await tester.pump();

    expect(find.text('(B)ASS'), findsOneWidget);
    expect(find.text('Añadir música'), findsOneWidget);
  });
}
