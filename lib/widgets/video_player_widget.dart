// ignore_for_file: deprecated_member_use, avoid_print
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';

class VideoPlayerWidget extends StatefulWidget {
  final String videoPath;
  final VideoPlayerController controller;
  final bool isActive;
  final bool isMuted;
  final double playbackSpeed;
  final double longPressSpeed;
  final bool isFavorite;
  final bool isLandscape;
  final VoidCallback onMuteToggled;
  final ValueChanged<double> onSpeedChanged;
  final VoidCallback onShare;
  final VoidCallback onSettings;
  final bool autoScrollEnabled;
  final VoidCallback onAutoScrollToggled;
  final VoidCallback onDelete;
  final VoidCallback onFavoriteToggled;
  final VoidCallback onRotateScreen;

  const VideoPlayerWidget({
    super.key,
    required this.videoPath,
    required this.controller,
    required this.isActive,
    required this.isMuted,
    required this.playbackSpeed,
    this.longPressSpeed = 2.0,
    this.isFavorite = false,
    this.isLandscape = false,
    required this.onMuteToggled,
    required this.onSpeedChanged,
    required this.onShare,
    required this.onSettings,
    required this.autoScrollEnabled,
    required this.onAutoScrollToggled,
    required this.onDelete,
    required this.onFavoriteToggled,
    required this.onRotateScreen,
  });

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> with TickerProviderStateMixin {
  bool _showPlayOverlay = false;
  bool _isPlayOverlayIconPlay = true;
  bool _showMuteOverlay = false;
  
  // Continuous touch / long-press fast forward state (like Facebook/TikTok)
  bool _isFastForwarding = false;
  bool _wasPlayingBeforeFastForward = true;

  // Custom double-tap tracker
  int _lastTapTime = 0;
  Timer? _tapTimer;

  @override
  void dispose() {
    _tapTimer?.cancel();
    super.dispose();
  }

  void _handleTap() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastTapTime < 300) {
      // Double tap detected -> toggle mute
      _tapTimer?.cancel();
      _toggleMute();
    } else {
      // Single tap detected - wait to see if it's a double tap
      _tapTimer?.cancel();
      _tapTimer = Timer(const Duration(milliseconds: 250), () {
        if (!_isFastForwarding && mounted) {
          _togglePlay();
        }
      });
    }
    _lastTapTime = now;
  }

  // Continuous touch speed up (Facebook / TikTok feature)
  void _startFastForward() {
    if (!widget.controller.value.isInitialized) return;
    _tapTimer?.cancel();
    _wasPlayingBeforeFastForward = widget.controller.value.isPlaying;
    _isFastForwarding = true;
    widget.controller.setPlaybackSpeed(widget.longPressSpeed);
    if (!_wasPlayingBeforeFastForward) {
      widget.controller.play();
    }
    HapticFeedback.lightImpact();
    setState(() {});
  }

  void _stopFastForward() {
    if (!_isFastForwarding) return;
    _isFastForwarding = false;
    widget.controller.setPlaybackSpeed(widget.playbackSpeed);
    if (!_wasPlayingBeforeFastForward) {
      widget.controller.pause();
    }
    setState(() {});
  }

  void _togglePlay() {
    if (!widget.controller.value.isInitialized) return;
    
    setState(() {
      if (widget.controller.value.isPlaying) {
        widget.controller.pause();
        _isPlayOverlayIconPlay = false;
      } else {
        widget.controller.play();
        _isPlayOverlayIconPlay = true;
      }
      _showPlayOverlay = true;
    });

    Future.delayed(const Duration(milliseconds: 650), () {
      if (mounted) {
        setState(() {
          _showPlayOverlay = false;
        });
      }
    });
  }

  void _toggleMute() {
    widget.onMuteToggled();
    setState(() {
      _showMuteOverlay = true;
    });

    Future.delayed(const Duration(milliseconds: 650), () {
      if (mounted) {
        setState(() {
          _showMuteOverlay = false;
        });
      }
    });
  }

  void _seekToRelativePosition(double localX, BuildContext context) {
    final value = widget.controller.value;
    if (!value.isInitialized || value.duration == Duration.zero) return;

    final width = MediaQuery.of(context).size.width;
    final double relative = (localX / width).clamp(0.0, 1.0);
    final Duration position = value.duration * relative;
    
    widget.controller.seekTo(position);
  }

  void _showSpeedSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final speeds = [0.5, 0.75, 1.0, 1.1, 1.2, 1.5, 1.8, 2.0];
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF121212),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(
              top: BorderSide(color: Colors.white10, width: 1),
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 12, bottom: 16),
                  child: Text(
                    'Playback Speed',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: speeds.map((speed) {
                    final isSelected = widget.playbackSpeed == speed;
                    return InkWell(
                      onTap: () {
                        widget.onSpeedChanged(speed);
                        Navigator.pop(context);
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFF00F2FE).withOpacity(0.15) : Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected ? const Color(0xFF00F2FE) : Colors.white10,
                            width: 1.5,
                          ),
                        ),
                        child: Text(
                          speed == 1.0 ? '1.0x (Normal)' : '${speed}x',
                          style: TextStyle(
                            color: isSelected ? const Color(0xFF00F2FE) : Colors.white70,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback onPressed,
    Color iconColor = Colors.white,
    Color? borderColor,
    String? label,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: onPressed,
            icon: Icon(icon, color: iconColor, size: 22),
            style: IconButton.styleFrom(
              backgroundColor: Colors.black54,
              shape: const CircleBorder(),
              padding: const EdgeInsets.all(11),
              side: BorderSide(color: borderColor ?? Colors.white12, width: 0.5),
            ),
          ),
          if (label != null) ...[
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                shadows: [
                  Shadow(offset: Offset(0, 1), blurRadius: 3, color: Colors.black),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fileName = p.basename(widget.videoPath);
    final value = widget.controller.value;
    final isInitialized = value.isInitialized;
    
    // Determine video aspect ratio and layout fit
    final isPortrait = isInitialized && (value.aspectRatio < 1.0);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        alignment: Alignment.center,
        children: [
          // Video Player Core with Tap and Continuous Touch (Long Press) Listener
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _handleTap,
            onLongPressStart: (_) => _startFastForward(),
            onLongPressEnd: (_) => _stopFastForward(),
            onLongPressCancel: () => _stopFastForward(),
            child: SizedBox.expand(
              child: isInitialized
                  ? FittedBox(
                      fit: (isPortrait && !widget.isLandscape) ? BoxFit.cover : BoxFit.contain,
                      child: SizedBox(
                        width: value.size.width,
                        height: value.size.height,
                        child: VideoPlayer(widget.controller),
                      ),
                    )
                  : _buildLoadingWidget(),
            ),
          ),

          // Double Tap / Single Tap Flash Overlay Animations
          if (_showPlayOverlay)
            IgnorePointer(
              child: AnimatedOpacity(
                opacity: _showPlayOverlay ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 150),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Icon(
                    _isPlayOverlayIconPlay ? Icons.play_arrow_rounded : Icons.pause_rounded,
                    size: 64,
                    color: const Color(0xFF00F2FE),
                  ),
                ),
              ),
            ),

          if (_showMuteOverlay)
            IgnorePointer(
              child: AnimatedOpacity(
                opacity: _showMuteOverlay ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 150),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Icon(
                    widget.isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    size: 64,
                    color: const Color(0xFF00F2FE),
                  ),
                ),
              ),
            ),

          // Continuous Touch Speed Up Badge (Like Facebook / TikTok)
          if (_isFastForwarding)
            Positioned(
              top: MediaQuery.of(context).padding.top + 20,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.75),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFF00F2FE), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00F2FE).withOpacity(0.35),
                        blurRadius: 14,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.speed_rounded, color: Color(0xFF00F2FE), size: 18),
                      const SizedBox(width: 8),
                      Text(
                        '${widget.longPressSpeed}x Speed >>',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // TOP NAVIGATION / OVERLAY BUTTONS (Folders & Auto-Scroll status)
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Auto Scroll status indicator (acts as button to toggle)
                GestureDetector(
                  onTap: widget.onAutoScrollToggled,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: widget.autoScrollEnabled
                            ? const Color(0xFF00F2FE).withOpacity(0.5)
                            : Colors.white24,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.play_circle_fill_rounded,
                          size: 14,
                          color: widget.autoScrollEnabled
                              ? const Color(0xFF00F2FE)
                              : Colors.white70,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          widget.autoScrollEnabled ? 'AUTO SCROLL ON' : 'AUTO SCROLL OFF',
                          style: TextStyle(
                            color: widget.autoScrollEnabled
                                ? const Color(0xFF00F2FE)
                                : Colors.white70,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Folder & Settings management button
                IconButton(
                  onPressed: widget.onSettings,
                  icon: const Icon(Icons.folder_copy_rounded, color: Colors.white),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black45,
                    shape: const CircleBorder(),
                    padding: const EdgeInsets.all(12),
                  ),
                ),
              ],
            ),
          ),

          // BOTTOM METADATA & CONTROL PANEL
          Positioned(
            bottom: 24,
            left: 16,
            right: 16,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Video Info (Left side)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Video Title (Clean look)
                      Text(
                        fileName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          shadows: [
                            Shadow(
                              offset: Offset(0, 1.5),
                              blurRadius: 3.0,
                              color: Colors.black87,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      
                      // Playback Speed pill button
                      GestureDetector(
                        onTap: _showSpeedSelector,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white24, width: 0.5),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.speed_rounded, size: 14, color: Color(0xFF00F2FE)),
                              const SizedBox(width: 4),
                              Text(
                                '${widget.playbackSpeed}x',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(width: 12),
                
                // Actions Column (Right side)
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.7,
                  ),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 1. Favorite Icon
                        _buildActionButton(
                          icon: widget.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          iconColor: widget.isFavorite ? const Color(0xFFFF2D55) : Colors.white,
                          borderColor: widget.isFavorite ? const Color(0xFFFF2D55).withOpacity(0.5) : null,
                          label: 'Fav',
                          onPressed: widget.onFavoriteToggled,
                        ),

                        // 2. Rotate Screen
                        _buildActionButton(
                          icon: widget.isLandscape ? Icons.screen_lock_portrait_rounded : Icons.screen_rotation_rounded,
                          iconColor: Colors.white,
                          label: 'Rotate',
                          onPressed: widget.onRotateScreen,
                        ),

                        // 5. Mute Shortcut button
                        _buildActionButton(
                          icon: widget.isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                          iconColor: Colors.white,
                          onPressed: widget.onMuteToggled,
                        ),

                        // 6. Share button
                        _buildActionButton(
                          icon: Icons.share_rounded,
                          iconColor: Colors.white,
                          onPressed: widget.onShare,
                        ),

                        // 7. Delete button
                        _buildActionButton(
                          icon: Icons.delete_forever_rounded,
                          iconColor: Colors.redAccent,
                          borderColor: Colors.redAccent.withOpacity(0.5),
                          onPressed: widget.onDelete,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ULTRAMINIMALISTIC PROGRESS BAR AT THE VERY BOTTOM (SEEKABLE)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) => _seekToRelativePosition(details.localPosition.dx, context),
              onHorizontalDragUpdate: (details) => _seekToRelativePosition(details.localPosition.dx, context),
              child: Container(
                height: 16,
                color: Colors.transparent,
                alignment: Alignment.bottomCenter,
                child: ValueListenableBuilder<VideoPlayerValue>(
                  valueListenable: widget.controller,
                  builder: (context, value, child) {
                    final progress = (value.isInitialized && value.duration > Duration.zero)
                        ? value.position.inMilliseconds / value.duration.inMilliseconds
                        : 0.0;
                    return Stack(
                      alignment: Alignment.bottomLeft,
                      children: [
                        // Background track
                        Container(
                          height: 4,
                          color: Colors.white12,
                        ),
                        // Active track
                        FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: progress.clamp(0.0, 1.0),
                          child: Container(
                            height: 4,
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Color(0xFF00F2FE), Color(0xFF4FACFE)],
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingWidget() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 56,
                  height: 56,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      const Color(0xFF00F2FE).withOpacity(0.8),
                    ),
                  ),
                ),
                const Icon(
                  Icons.play_arrow_rounded,
                  size: 28,
                  color: Colors.white70,
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Loading local video...',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 12,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
