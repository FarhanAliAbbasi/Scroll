import 'dart:math';

class VideoQueueManager {
  final List<String> allVideos; // All scanned or selected video paths
  final List<String> history = []; // History of video paths shown in PageView
  final Random _random = Random();

  VideoQueueManager(this.allVideos);

  bool get isEmpty => allVideos.isEmpty;
  int get totalVideosCount => allVideos.length;

  // Maximum number of recent videos to avoid repeating (20-25 range)
  static const int recentAvoidCount = 25;

  // Retrieve a video path for a specific index in the PageView
  String? getVideoForIndex(int index) {
    if (isEmpty) return null;

    // If the PageView is asking for an index we have already generated, return from history
    if (index < history.length) {
      return history[index];
    }

    // Otherwise, generate random videos until history is populated up to this index
    while (history.length <= index) {
      String selected;
      if (allVideos.length > 1) {
        // Avoid repeating any video from the last 20 to 25 entries in history
        final int avoidWindow = min(recentAvoidCount, max(1, allVideos.length - 1));
        final int startIdx = max(0, history.length - avoidWindow);
        final Set<String> recentVideos = history.sublist(startIdx).toSet();

        // Candidates are videos not played in the recent avoid window
        final candidates = allVideos.where((v) => !recentVideos.contains(v)).toList();

        if (candidates.isNotEmpty) {
          selected = candidates[_random.nextInt(candidates.length)];
        } else {
          // Fallback: avoid at least the immediately preceding video
          final lastVideo = history.isNotEmpty ? history.last : null;
          final fallbackCandidates = allVideos.where((v) => v != lastVideo).toList();
          if (fallbackCandidates.isNotEmpty) {
            selected = fallbackCandidates[_random.nextInt(fallbackCandidates.length)];
          } else {
            selected = allVideos[_random.nextInt(allVideos.length)];
          }
        }
      } else {
        selected = allVideos[0];
      }
      history.add(selected);
    }

    return history[index];
  }

  // Insert a new video (e.g. newly uploaded) at the next position or pool
  void addVideo(String path) {
    if (!allVideos.contains(path)) {
      allVideos.add(path);
    }
  }

  // Remove a video from pool and history (e.g. when deleted)
  void removeVideo(String path) {
    allVideos.remove(path);
    history.removeWhere((v) => v == path);
  }

  // Clear history to start a fresh feed
  void clearHistory() {
    history.clear();
  }
}
