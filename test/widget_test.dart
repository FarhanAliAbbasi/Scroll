import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:scroll/main.dart';
import 'package:scroll/models/video_queue_manager.dart';
import 'package:scroll/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Smoke test for ScrollApp welcome screen', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const ScrollApp());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    expect(find.text('Scroll'), findsOneWidget);
    expect(find.text('Configure Video Sources'), findsOneWidget);
  });

  test('VideoQueueManager avoids repeating last 20 to 25 videos', () {
    // Create a pool of 50 videos
    final videos = List.generate(50, (i) => '/path/to/video_$i.mp4');
    final queue = VideoQueueManager(videos);

    // Generate 35 items
    for (int i = 0; i < 35; i++) {
      final video = queue.getVideoForIndex(i);
      expect(video, isNotNull);
    }

    // Check that at any point after 25 items, an item doesn't match the last 20-25 items
    for (int i = 25; i < 35; i++) {
      final current = queue.history[i];
      // Recent 20 items before index i
      final recent = queue.history.sublist(i - 20, i);
      expect(recent.contains(current), isFalse,
          reason: 'Video $current at index $i was repeated within last 20 items: $recent');
    }
  });

  test('StorageService persists background audio, hold speed & favorites', () async {
    SharedPreferences.setMockInitialValues({});

    // Background Audio
    expect(await StorageService.getBackgroundAudio(), isFalse);
    await StorageService.saveBackgroundAudio(true);
    expect(await StorageService.getBackgroundAudio(), isTrue);

    // Long press hold speed
    expect(await StorageService.getLongPressSpeed(), 2.0);
    await StorageService.saveLongPressSpeed(2.5);
    expect(await StorageService.getLongPressSpeed(), 2.5);

    // Favorites
    const testVideo = '/storage/emulated/0/DCIM/clip1.mp4';
    expect(await StorageService.isFavorite(testVideo), isFalse);
    final isFav = await StorageService.toggleFavorite(testVideo);
    expect(isFav, isTrue);
    expect(await StorageService.isFavorite(testVideo), isTrue);
  });
}
