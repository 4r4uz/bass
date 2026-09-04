import 'package:flutter_test/flutter_test.dart';
import 'package:bass/main.dart';
import 'package:bass/services/library_store.dart';
import 'package:bass/src/rust/frb_generated.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => await RustLib.init());
  testWidgets('Can call rust function', (WidgetTester tester) async {
    await tester.pumpWidget(
      MyApp(library: LibraryStore(), initialTracks: const []),
    );
    expect(find.textContaining('Result: `Hello, Tom!`'), findsOneWidget);
  });
}
