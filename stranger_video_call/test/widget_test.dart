import 'package:flutter_test/flutter_test.dart';

import 'package:stranger_video_call/main.dart';

void main() {
  testWidgets('Stranger Video Call app loads', (WidgetTester tester) async {
    await tester.pumpWidget(const StrangerVideoCallApp());

    expect(find.text('Stranger Video Call'), findsOneWidget);

    expect(find.text('Create Room'), findsOneWidget);

    expect(find.text('Join Room'), findsOneWidget);
  });
}
