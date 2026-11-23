import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:filebrowser_mobile/src/ui/audio_player_screen.dart';

import 'support/l10n.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('full-screen audio error is copyable', (tester) async {
    // No video_player platform plugin is registered in unit tests, so
    // controller.initialize() throws and the screen falls into its error
    // state — exactly the surface we want to exercise.
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );

    await tester.pumpWidget(
      l10nWrap(
        AudioPlayerScreen(
          url: Uri.parse('https://example.com/song.mp3'),
          headers: const {'Authorization': 'Bearer token'},
          title: 'song.mp3',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not play audio:'), findsOneWidget);
    final copyBtn = find.widgetWithText(OutlinedButton, 'Copy');
    expect(copyBtn, findsOneWidget);

    await tester.tap(copyBtn);
    await tester.pump();

    expect(copied, isNotNull);
    expect(copied, startsWith('Could not play audio:'));

    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });
}
