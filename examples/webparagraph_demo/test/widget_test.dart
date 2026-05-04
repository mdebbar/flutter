import 'package:flutter_test/flutter_test.dart';
import 'package:webparagraph_demo/main.dart';

void main() {
  testWidgets('WebParagraph Demo smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const WebParagraphDemoApp());

    // Verify that the title is present.
    expect(find.text('WEB\nPARAGRAPH'), findsOneWidget);
    
    // Verify that we have the sections listed.
    expect(find.text('Polyglot Text'), findsWidgets);
    expect(find.text('Native Emojis'), findsWidgets);
  });
}
