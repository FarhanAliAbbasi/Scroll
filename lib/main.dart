// ignore_for_file: deprecated_member_use, avoid_print
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import 'package:scroll/services/storage_service.dart';
import 'package:scroll/models/video_queue_manager.dart';
import 'package:scroll/widgets/video_player_widget.dart';
import 'package:scroll/widgets/settings_sheet.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Set system UI style to full-screen immersive dark mode
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.black,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  
  runApp(const ScrollApp());
}

class ScrollApp extends StatelessWidget {
  const ScrollApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Scroll - Local Video Feed',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00F2FE),
          secondary: Color(0xFF4FACFE),
          surface: Color(0xFF0F0F0F),
        ),
        fontFamily: 'Roboto',
      ),
      home: const FeedScreen(),
    );
  }
}

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> with WidgetsBindingObserver {
  final PageController _pageController = PageController();
  VideoQueueManager? _queueManager;
  
  List<String> _selectedFolders = [];
  List<String> _selectedFiles = [];
  bool _autoScrollEnabled = false;
  double _playbackSpeed = 1.0;
  bool _isMuted = false;
  
  // Features: Background Audio, Continuous Touch Speed, Favorites, Orientation
  bool _backgroundAudioEnabled = false;
  double _longPressSpeed = 2.0;
  List<String> _favorites = [];
  String _feedFilter = 'all'; // 'all', 'favorites'
  bool _isLandscape = false;

  bool _isLoading = true;
  int _currentIndex = 0;

  // Sliding window cache for players
  final Map<int, VideoPlayerController> _controllers = {};
  final Map<int, Future<void>> _initializeFutures = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSavedSettingsAndScan();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    try {
      WakelockPlus.disable();
    } catch (_) {}
    _disposeAllControllers();
    _pageController.dispose();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  // Handle app background/foreground transitions
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final activeController = _controllers[_currentIndex];
    if (activeController == null || !activeController.value.isInitialized) return;
    
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // If user enabled background audio, keep sound playing in background!
      if (!_backgroundAudioEnabled) {
        activeController.pause();
      }
    } else if (state == AppLifecycleState.resumed) {
      activeController.play();
    }
  }

  Future<void> _loadSavedSettingsAndScan() async {
    final folders = await StorageService.getSavedFolders();
    final files = await StorageService.getSavedFiles();
    final autoScroll = await StorageService.getAutoScroll();
    final speed = await StorageService.getDefaultSpeed();
    final bgAudio = await StorageService.getBackgroundAudio();
    final lpSpeed = await StorageService.getLongPressSpeed();
    final favs = await StorageService.getFavorites();

    if (mounted) {
      setState(() {
        _selectedFolders = folders;
        _selectedFiles = files;
        _autoScrollEnabled = autoScroll;
        _playbackSpeed = speed;
        _backgroundAudioEnabled = bgAudio;
        _longPressSpeed = lpSpeed;
        _favorites = favs;
      });
    }

    if (_selectedFolders.isNotEmpty || _selectedFiles.isNotEmpty) {
      await _scanAndLoadVideos();
    } else {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _scanAndLoadVideos({String? playlistType}) async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        if (playlistType != null) {
          _feedFilter = playlistType;
        }
      });
    }

    List<String> pooledVideos = [];

    if (_feedFilter == 'favorites') {
      for (final p in _favorites) {
        if (await File(p).exists()) {
          pooledVideos.add(p);
        }
      }
    } else {
      // Scan folders
      if (_selectedFolders.isNotEmpty) {
        final scanned = await StorageService.scanFoldersForVideos(_selectedFolders);
        pooledVideos.addAll(scanned);
      }

      // Add direct files
      for (final filePath in _selectedFiles) {
        if (await File(filePath).exists()) {
          pooledVideos.add(filePath);
        }
      }
    }

    // Deduplicate
    pooledVideos = pooledVideos.toSet().toList();

    if (mounted) {
      setState(() {
        _queueManager = VideoQueueManager(pooledVideos);
      });
    }

    await _initFeed();
  }

  Future<void> _initFeed() async {
    _disposeAllControllers();
    
    final queue = _queueManager;
    if (queue == null || queue.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }

    if (_pageController.hasClients) {
      _pageController.jumpToPage(0);
    }
    
    if (mounted) {
      setState(() {
        _currentIndex = 0;
      });
    }

    // Load first video player immediately
    await _playVideo(0);

    // Preload next player in background
    _preloadVideo(1);

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _preloadVideo(int index) async {
    final queue = _queueManager;
    if (queue == null || index < 0) return;
    
    final path = queue.getVideoForIndex(index);
    if (path == null) return;
    
    if (_controllers.containsKey(index)) return; // Already loading/loaded

    final file = File(path);
    if (!await file.exists()) return;

    final controller = VideoPlayerController.file(file);
    _controllers[index] = controller;
    
    final future = controller.initialize().then((_) {
      if (mounted) {
        setState(() {}); // Update to trigger build once initialized
      }
      controller.setLooping(!_autoScrollEnabled);
      controller.setVolume(_isMuted ? 0.0 : 1.0);
      controller.setPlaybackSpeed(_playbackSpeed);
    }).catchError((error) {
      print("Preload error at index $index: $error");
    });
    
    _initializeFutures[index] = future;
  }

  Future<void> _playVideo(int index) async {
    final queue = _queueManager;
    if (queue == null || index < 0) return;

    if (!_controllers.containsKey(index)) {
      await _preloadVideo(index);
    }

    final controller = _controllers[index];
    if (controller != null) {
      _setupCompletionListener(index, controller);
      
      final initFuture = _initializeFutures[index];
      if (initFuture != null) {
        await initFuture;
      }

      if (_currentIndex == index && mounted) {
        await controller.seekTo(Duration.zero);
        controller.play();
        _updateWakelockState();
      }
    }

    // Pause all other controllers
    _controllers.forEach((idx, ctrl) {
      if (idx != index) {
        ctrl.pause();
      }
    });
  }

  void _setupCompletionListener(int index, VideoPlayerController controller) {
    controller.addListener(() {
      if (index != _currentIndex) return;
      
      final val = controller.value;
      _updateWakelockState();

      if (val.isInitialized && 
          val.position >= val.duration && 
          val.duration > Duration.zero && 
          !val.isPlaying) {
        
        if (_autoScrollEnabled) {
          _scrollToNext();
        }
      }
    });
  }

  void _updateWakelockState() {
    try {
      final activeCtrl = _controllers[_currentIndex];
      if (activeCtrl != null && activeCtrl.value.isPlaying) {
        WakelockPlus.enable();
      } else {
        WakelockPlus.disable();
      }
    } catch (_) {}
  }

  void _scrollToNext() {
    if (_pageController.hasClients) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _onPageChanged(int index) async {
    if (mounted) {
      setState(() {
        _currentIndex = index;
      });
    }

    // Play current index
    await _playVideo(index);

    // Preload next and previous indices
    _preloadVideo(index + 1);
    if (index > 0) {
      _preloadVideo(index - 1);
    }

    // Clean up controllers outside of sliding window [index - 1, index + 1]
    _cleanUpControllers(index);
  }

  void _cleanUpControllers(int activeIndex) {
    final keysToDispose = _controllers.keys
        .where((idx) => idx < activeIndex - 1 || idx > activeIndex + 1)
        .toList();
        
    for (final idx in keysToDispose) {
      _controllers[idx]?.dispose();
      _controllers.remove(idx);
      _initializeFutures.remove(idx);
    }
  }

  void _disposeAllControllers() {
    _controllers.forEach((idx, ctrl) {
      ctrl.dispose();
    });
    _controllers.clear();
    _initializeFutures.clear();
  }

  void _toggleMuteState() {
    if (mounted) {
      setState(() {
        _isMuted = !_isMuted;
      });
    }

    _controllers.forEach((idx, ctrl) {
      ctrl.setVolume(_isMuted ? 0.0 : 1.0);
    });
  }

  void _changePlaybackSpeed(double speed) {
    if (mounted) {
      setState(() {
        _playbackSpeed = speed;
      });
    }
    StorageService.saveDefaultSpeed(speed);

    _controllers.forEach((idx, ctrl) {
      ctrl.setPlaybackSpeed(speed);
    });
  }

  void _toggleAutoScrollState() {
    if (mounted) {
      setState(() {
        _autoScrollEnabled = !_autoScrollEnabled;
      });
    }
    StorageService.saveAutoScroll(_autoScrollEnabled);

    _controllers.forEach((idx, ctrl) {
      ctrl.setLooping(!_autoScrollEnabled);
    });
  }

  // Rotate screen orientation
  void _toggleOrientation() {
    setState(() {
      _isLandscape = !_isLandscape;
    });

    if (_isLandscape) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
    }
  }

  // Favorite toggle
  Future<void> _toggleFavorite() async {
    final queue = _queueManager;
    if (queue == null) return;
    
    final path = queue.getVideoForIndex(_currentIndex);
    if (path == null) return;

    final isFav = await StorageService.toggleFavorite(path);
    final favs = await StorageService.getFavorites();
    if (mounted) {
      setState(() {
        _favorites = favs;
      });
      _showSnackBar(isFav ? 'Added to Favorites ❤️' : 'Removed from Favorites');
    }
  }

  Future<void> _shareCurrentVideo() async {
    final queue = _queueManager;
    if (queue == null) return;
    
    final path = queue.getVideoForIndex(_currentIndex);
    if (path == null) return;

    try {
      final file = File(path);
      if (await file.exists()) {
        final name = p.basename(path);
        await SharePlus.instance.share(ShareParams(
          files: [XFile(path)],
          text: 'Check out: $name',
        ));
      } else {
        _showSnackBar('Video file not found.');
      }
    } catch (e) {
      _showSnackBar('Failed to share video: $e');
    }
  }

  Future<void> _deleteCurrentVideo() async {
    final queue = _queueManager;
    if (queue == null) return;
    
    final path = queue.getVideoForIndex(_currentIndex);
    if (path == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Video?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'This will permanently delete "${p.basename(path)}" from your device storage.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final activeCtrl = _controllers[_currentIndex];
      await activeCtrl?.pause();
      
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }

      queue.removeVideo(path);
      _selectedFiles.remove(path);
      _favorites.remove(path);
      await StorageService.saveFiles(_selectedFiles);
      await StorageService.saveFavorites(_favorites);

      _showSnackBar('Video deleted successfully.');

      if (queue.isEmpty) {
        _disposeAllControllers();
        setState(() {
          _queueManager = null;
        });
      } else {
        _disposeAllControllers();
        
        if (_currentIndex >= queue.allVideos.length) {
          _currentIndex = max(0, queue.allVideos.length - 1);
        }

        setState(() {
          _isLoading = true;
        });
        
        await _playVideo(_currentIndex);
        _preloadVideo(_currentIndex + 1);
        if (_currentIndex > 0) {
          _preloadVideo(_currentIndex - 1);
        }
        
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      _showSnackBar('Failed to delete video: $e');
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showSettings() {
    final activeCtrl = _controllers[_currentIndex];
    final wasPlaying = activeCtrl?.value.isPlaying ?? false;
    
    if (wasPlaying) {
      activeCtrl?.pause();
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.9,
          child: SettingsSheet(
            folders: _selectedFolders,
            files: _selectedFiles,
            autoScroll: _autoScrollEnabled,
            defaultSpeed: _playbackSpeed,
            backgroundAudio: _backgroundAudioEnabled,
            longPressSpeed: _longPressSpeed,
            favorites: _favorites,
            totalVideosScanned: _queueManager?.totalVideosCount ?? 0,
            onPlayPlaylist: (playlist) async {
              await _scanAndLoadVideos(playlistType: playlist);
            },
            onSettingsSaved: (folders, files, autoScroll, defaultSpeed, backgroundAudio, longPressSpeed) async {
              setState(() {
                _selectedFolders = folders;
                _selectedFiles = files;
                _autoScrollEnabled = autoScroll;
                _playbackSpeed = defaultSpeed;
                _backgroundAudioEnabled = backgroundAudio;
                _longPressSpeed = longPressSpeed;
              });
              await _scanAndLoadVideos();
            },
          ),
        );
      },
    ).then((_) {
      if (wasPlaying && mounted) {
        _controllers[_currentIndex]?.play();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final queue = _queueManager;

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00F2FE)),
          ),
        ),
      );
    }

    if (queue == null || queue.isEmpty) {
      return _buildWelcomeScreen();
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            itemCount: 999999, // Simulate infinite scrolling
            onPageChanged: _onPageChanged,
            physics: const BouncingScrollPhysics(parent: PageScrollPhysics()),
            itemBuilder: (context, index) {
              final videoPath = queue.getVideoForIndex(index);
              if (videoPath == null) {
                return const SizedBox();
              }

              final controller = _controllers[index];
              if (controller == null) {
                return Container(
                  color: Colors.black,
                  child: const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00F2FE)),
                    ),
                  ),
                );
              }

              return VideoPlayerWidget(
                videoPath: videoPath,
                controller: controller,
                isActive: index == _currentIndex,
                isMuted: _isMuted,
                playbackSpeed: _playbackSpeed,
                longPressSpeed: _longPressSpeed,
                isFavorite: _favorites.contains(videoPath),
                isLandscape: _isLandscape,
                onMuteToggled: _toggleMuteState,
                onSpeedChanged: _changePlaybackSpeed,
                onShare: _shareCurrentVideo,
                onSettings: _showSettings,
                autoScrollEnabled: _autoScrollEnabled,
                onAutoScrollToggled: _toggleAutoScrollState,
                onDelete: _deleteCurrentVideo,
                onFavoriteToggled: _toggleFavorite,
                onRotateScreen: _toggleOrientation,
              );
            },
          ),

          // Playlist filter banner if viewing Favorites
          if (_feedFilter == 'favorites')
            Positioned(
              top: MediaQuery.of(context).padding.top + 54,
              left: 16,
              child: GestureDetector(
                onTap: () => _scanAndLoadVideos(playlistType: 'all'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF2D55).withOpacity(0.85),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.favorite_rounded,
                        size: 13,
                        color: Colors.white,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Favorites (Tap to Exit)',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWelcomeScreen() {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.black, Color(0xFF0F172A)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 16),
                    
                    // Logo/Icon
                    Center(
                      child: Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(32),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF00F2FE).withOpacity(0.3),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(32),
                          child: Image.asset(
                            'assets/logo.png',
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    
                    // App Name
                    Center(
                      child: Text(
                        'Scroll',
                        style: TextStyle(
                          fontSize: 44,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                          foreground: Paint()
                            ..shader = const LinearGradient(
                              colors: [Color(0xFF00F2FE), Color(0xFF4FACFE)],
                            ).createShader(const Rect.fromLTWH(0.0, 0.0, 200.0, 70.0)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    // Subtitle
                    const Center(
                      child: Text(
                        'Your local video directory, re-imagined as a distraction-free vertical feed.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 36),

                    // Feature Details
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white10, width: 0.5),
                      ),
                      child: const Column(
                        children: [
                          _FeatureRow(
                            icon: Icons.folder_open_rounded,
                            title: 'Pick Folders & Upload',
                            desc: 'Scan device directories or upload video files directly.',
                          ),
                          SizedBox(height: 16),
                          _FeatureRow(
                            icon: Icons.shuffle_rounded,
                            title: 'Random Shuffled Queue',
                            desc: 'Avoids repeating the last 20-25 videos in the feed.',
                          ),
                          SizedBox(height: 16),
                          _FeatureRow(
                            icon: Icons.speed_rounded,
                            title: 'Touch & Hold Speed Up',
                            desc: 'Hold screen to fast-forward like Facebook & TikTok.',
                          ),
                          SizedBox(height: 16),
                          _FeatureRow(
                            icon: Icons.music_note_rounded,
                            title: 'Background Audio & Favorites',
                            desc: 'Play sound in background, save & enjoy favorite videos.',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 36),

                    // Welcome Buttons
                    ElevatedButton(
                      onPressed: _showSettings,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ).copyWith(
                        backgroundColor: WidgetStateProperty.resolveWith((states) => Colors.transparent),
                      ),
                      child: Ink(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF00F2FE), Color(0xFF4FACFE)],
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Container(
                          alignment: Alignment.center,
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.folder_copy_rounded, color: Colors.black, size: 20),
                              SizedBox(width: 10),
                              Text(
                                'Configure Video Sources',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;

  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.desc,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF00F2FE).withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: const Color(0xFF00F2FE), size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                desc,
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
