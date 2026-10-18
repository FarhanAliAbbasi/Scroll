// ignore_for_file: deprecated_member_use, avoid_print
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const String _keyFolders = 'selected_folders';
  static const String _keySelectedFiles = 'selected_files';
  static const String _keyAutoScroll = 'auto_scroll';
  static const String _keyDefaultSpeed = 'default_speed';
  static const String _keyBackgroundAudio = 'background_audio';
  static const String _keyLongPressSpeed = 'long_press_speed';
  static const String _keyFavorites = 'favorite_videos';

  static final List<String> videoExtensions = [
    '.mp4',
    '.mkv',
    '.mov',
    '.webm',
    '.3gp',
    '.avi'
  ];

  // Request permissions depending on platform
  static Future<bool> requestStoragePermission() async {
    if (Platform.isAndroid) {
      // For Android 11+ (API 30+), check and request Manage External Storage
      if (await Permission.manageExternalStorage.isGranted) {
        return true;
      }
      
      final status = await Permission.manageExternalStorage.request();
      if (status.isGranted) {
        return true;
      }
      
      // Fallback/Legacy permissions for older Android versions
      final storageStatus = await Permission.storage.request();
      if (storageStatus.isGranted) {
        return true;
      }

      final videoStatus = await Permission.videos.request();
      return videoStatus.isGranted;
    } else if (Platform.isIOS) {
      // Photo Library usage for iOS
      final status = await Permission.photos.request();
      return status.isGranted || status.isLimited;
    }
    return true;
  }

  // Check if storage permission is granted
  static Future<bool> hasStoragePermission() async {
    if (Platform.isAndroid) {
      if (await Permission.manageExternalStorage.isGranted) return true;
      if (await Permission.storage.isGranted) return true;
      return await Permission.videos.isGranted;
    } else if (Platform.isIOS) {
      final status = await Permission.photos.status;
      return status.isGranted || status.isLimited;
    }
    return true;
  }

  // Open App Settings page if permissions are permanently denied
  static Future<void> openAppSettingsPage() async {
    await openAppSettings();
  }

  // Get saved folder paths
  static Future<List<String>> getSavedFolders() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_keyFolders) ?? [];
  }

  // Save folder paths
  static Future<void> saveFolders(List<String> folders) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyFolders, folders);
  }

  // Get saved files (direct select fallback)
  static Future<List<String>> getSavedFiles() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_keySelectedFiles) ?? [];
  }

  // Save files (direct select fallback)
  static Future<void> saveFiles(List<String> files) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keySelectedFiles, files);
  }

  // Settings: Auto Scroll
  static Future<bool> getAutoScroll() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAutoScroll) ?? false;
  }

  static Future<void> saveAutoScroll(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoScroll, value);
  }

  // Settings: Default Speed
  static Future<double> getDefaultSpeed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_keyDefaultSpeed) ?? 1.0;
  }

  static Future<void> saveDefaultSpeed(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyDefaultSpeed, value);
  }

  // Settings: Background Audio Playback
  static Future<bool> getBackgroundAudio() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyBackgroundAudio) ?? false;
  }

  static Future<void> saveBackgroundAudio(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyBackgroundAudio, value);
  }

  // Settings: Long-Press Continuous Touch Speed
  static Future<double> getLongPressSpeed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_keyLongPressSpeed) ?? 2.0;
  }

  static Future<void> saveLongPressSpeed(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyLongPressSpeed, value);
  }

  // Library: Favorites
  static Future<List<String>> getFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_keyFavorites) ?? [];
  }

  static Future<void> saveFavorites(List<String> favorites) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyFavorites, favorites);
  }

  static Future<bool> isFavorite(String path) async {
    final list = await getFavorites();
    return list.contains(path);
  }

  static Future<bool> toggleFavorite(String path) async {
    final list = await getFavorites();
    bool isNowFav;
    if (list.contains(path)) {
      list.remove(path);
      isNowFav = false;
    } else {
      list.add(path);
      isNowFav = true;
    }
    await saveFavorites(list);
    return isNowFav;
  }

  // Scan multiple folders for video files
  static Future<List<String>> scanFoldersForVideos(List<String> folderPaths) async {
    final List<String> videoFiles = [];
    
    for (final folderPath in folderPaths) {
      try {
        final dir = Directory(folderPath);
        if (await dir.exists()) {
          // List files asynchronously to avoid UI jank
          await for (final entity in dir.list(recursive: true, followLinks: false)) {
            // Safeguard against extremely large folders
            if (videoFiles.length >= 1000) break;
            
            if (entity is File) {
              final ext = p.extension(entity.path).toLowerCase();
              if (videoExtensions.contains(ext)) {
                videoFiles.add(entity.path);
              }
            }
          }
        }
      } catch (e) {
        // Handle permissions or scanning errors on subfolders
        print("Error scanning folder $folderPath: $e");
      }
    }
    
    // Sort files to have a consistent scan starting point (which will be shuffled anyway)
    videoFiles.sort();
    return videoFiles;
  }
}
