// ignore_for_file: deprecated_member_use, avoid_print
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:scroll/services/storage_service.dart';

class SettingsSheet extends StatefulWidget {
  final List<String> folders;
  final List<String> files;
  final bool autoScroll;
  final double defaultSpeed;
  final bool backgroundAudio;
  final double longPressSpeed;
  final List<String> favorites;
  final int totalVideosScanned;
  final Function(
    List<String> folders,
    List<String> files,
    bool autoScroll,
    double defaultSpeed,
    bool backgroundAudio,
    double longPressSpeed,
  ) onSettingsSaved;
  final Function(String playlistType)? onPlayPlaylist; // 'all', 'favorites'

  const SettingsSheet({
    super.key,
    required this.folders,
    required this.files,
    required this.autoScroll,
    required this.defaultSpeed,
    required this.backgroundAudio,
    required this.longPressSpeed,
    required this.favorites,
    required this.totalVideosScanned,
    required this.onSettingsSaved,
    this.onPlayPlaylist,
  });

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  late List<String> _folders;
  late List<String> _files;
  late bool _autoScroll;
  late double _defaultSpeed;
  late bool _backgroundAudio;
  late double _longPressSpeed;
  late List<String> _favorites;
  bool _permissionDenied = false;

  @override
  void initState() {
    super.initState();
    _folders = List.from(widget.folders);
    _files = List.from(widget.files);
    _autoScroll = widget.autoScroll;
    _defaultSpeed = widget.defaultSpeed;
    _backgroundAudio = widget.backgroundAudio;
    _longPressSpeed = widget.longPressSpeed;
    _favorites = List.from(widget.favorites);
    _checkPermissionState();
  }

  Future<void> _checkPermissionState() async {
    final hasPerm = await StorageService.hasStoragePermission();
    if (mounted) {
      setState(() {
        _permissionDenied = !hasPerm;
      });
    }
  }

  Future<void> _requestPermission() async {
    final granted = await StorageService.requestStoragePermission();
    if (mounted) {
      setState(() {
        _permissionDenied = !granted;
      });
      if (granted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Storage permission granted successfully!')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Permission denied. Please enable storage permission in settings.'),
            duration: Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _addFolder() async {
    final granted = await StorageService.requestStoragePermission();
    if (!granted) {
      setState(() {
        _permissionDenied = true;
      });
      return;
    }

    try {
      final String? selectedDirectory = await FilePicker.getDirectoryPath();
      if (selectedDirectory != null) {
        if (_folders.contains(selectedDirectory)) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Folder is already added.')),
            );
          }
          return;
        }
        
        setState(() {
          _folders.add(selectedDirectory);
        });
        _saveAndNotify();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick directory: $e')),
        );
      }
    }
  }

  Future<void> _addFiles() async {
    try {
      final FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.video,
        allowMultiple: true,
      );

      if (result != null && result.paths.isNotEmpty) {
        final List<String> paths = result.paths.whereType<String>().toList();
        int addedCount = 0;
        
        setState(() {
          for (final path in paths) {
            if (!_files.contains(path)) {
              _files.add(path);
              addedCount++;
            }
          }
        });

        if (addedCount > 0) {
          _saveAndNotify();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Added $addedCount video file(s) successfully.')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick video files: $e')),
        );
      }
    }
  }

  void _removeFolder(int index) {
    setState(() {
      _folders.removeAt(index);
    });
    _saveAndNotify();
  }

  void _removeFile(int index) {
    setState(() {
      _files.removeAt(index);
    });
    _saveAndNotify();
  }

  void _removeFavorite(int index) async {
    setState(() {
      _favorites.removeAt(index);
    });
    await StorageService.saveFavorites(_favorites);
    _saveAndNotify();
  }

  void _saveAndNotify() {
    StorageService.saveFolders(_folders);
    StorageService.saveFiles(_files);
    StorageService.saveAutoScroll(_autoScroll);
    StorageService.saveDefaultSpeed(_defaultSpeed);
    StorageService.saveBackgroundAudio(_backgroundAudio);
    StorageService.saveLongPressSpeed(_longPressSpeed);
    
    widget.onSettingsSaved(
      _folders,
      _files,
      _autoScroll,
      _defaultSpeed,
      _backgroundAudio,
      _longPressSpeed,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F0F0F),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(color: Colors.white10, width: 1),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag Indicator
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Feed Configuration',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.done_all_rounded, size: 18, color: Color(0xFF00F2FE)),
                  label: const Text(
                    'Done',
                    style: TextStyle(color: Color(0xFF00F2FE), fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const Divider(color: Colors.white10, height: 24),

            // Main Settings Content (Scrollable)
            Flexible(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                shrinkWrap: true,
                children: [
                  // Video Stats Panel
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.03),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white10, width: 0.5),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStatItem('FOLDERS', '${_folders.length}'),
                        _buildStatItem('FILES', '${_files.length}'),
                        _buildStatItem('FAVORITES', '${_favorites.length}', accentColor: const Color(0xFFFF2D55)),
                        _buildStatItem(
                          'TOTAL POOL',
                          '${widget.totalVideosScanned}',
                          accentColor: const Color(0xFF4FACFE),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Permission Warning Alert (if applicable)
                  if (_permissionDenied) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Storage Permission Needed',
                                style: TextStyle(
                                  color: Colors.redAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'To scan folders and play local videos, this app needs storage/media permissions. Note: Android 11+ requires "All Files Access" to scan arbitrary directories.',
                            style: TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              ElevatedButton(
                                onPressed: _requestPermission,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.redAccent,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                child: const Text('Grant Access', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton(
                                onPressed: StorageService.openAppSettingsPage,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white70,
                                  side: const BorderSide(color: Colors.white24),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                child: const Text('Open Settings', style: TextStyle(fontSize: 12)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Settings Controls
                  const Text(
                    'PLAYBACK CONTROLS',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Background Audio Toggle (USER FEATURE)
                  SwitchListTile(
                    title: const Text('Play Sound in Background', style: TextStyle(color: Colors.white)),
                    subtitle: const Text(
                      'Keep audio playing when app is minimized or screen is locked',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    value: _backgroundAudio,
                    activeColor: const Color(0xFF00F2FE),
                    contentPadding: EdgeInsets.zero,
                    onChanged: (bool value) {
                      setState(() {
                        _backgroundAudio = value;
                      });
                      _saveAndNotify();
                    },
                  ),
                  const Divider(color: Colors.white10),

                  // Continuous Touch Speed (Facebook/TikTok feature)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Touch & Hold Speed', style: TextStyle(color: Colors.white)),
                    subtitle: Text(
                      'Playback speed while continuously touching screen: ${_longPressSpeed}x',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    trailing: DropdownButton<double>(
                      value: _longPressSpeed,
                      dropdownColor: const Color(0xFF1E1E1E),
                      underline: Container(),
                      style: const TextStyle(color: Color(0xFF00F2FE), fontWeight: FontWeight.bold),
                      items: [1.25, 1.5, 2.0, 2.5, 3.0].map((speed) {
                        return DropdownMenuItem<double>(
                          value: speed,
                          child: Text('${speed}x'),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _longPressSpeed = value;
                          });
                          _saveAndNotify();
                        }
                      },
                    ),
                  ),
                  const Divider(color: Colors.white10),
                  
                  // Auto Scroll Toggle
                  SwitchListTile(
                    title: const Text('Auto Scroll Feed', style: TextStyle(color: Colors.white)),
                    subtitle: const Text('Automatically advance to next random video when current ends', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    value: _autoScroll,
                    activeColor: const Color(0xFF00F2FE),
                    contentPadding: EdgeInsets.zero,
                    onChanged: (bool value) {
                      setState(() {
                        _autoScroll = value;
                      });
                      _saveAndNotify();
                    },
                  ),
                  const Divider(color: Colors.white10),

                  // Default Playback Speed
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Default Playback Speed', style: TextStyle(color: Colors.white)),
                    subtitle: Text('Default speed for new videos: ${_defaultSpeed}x', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    trailing: DropdownButton<double>(
                      value: _defaultSpeed,
                      dropdownColor: const Color(0xFF1E1E1E),
                      underline: Container(),
                      style: const TextStyle(color: Color(0xFF00F2FE), fontWeight: FontWeight.bold),
                      items: [0.5, 0.75, 1.0, 1.1, 1.2, 1.5, 1.8, 2.0].map((speed) {
                        return DropdownMenuItem<double>(
                          value: speed,
                          child: Text('${speed}x'),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _defaultSpeed = value;
                          });
                          _saveAndNotify();
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Favorites Section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.favorite_rounded, color: Color(0xFFFF2D55), size: 16),
                          const SizedBox(width: 6),
                          Text(
                            'FAVORITE VIDEOS (${_favorites.length})',
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ],
                      ),
                      if (_favorites.isNotEmpty && widget.onPlayPlaylist != null)
                        TextButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            widget.onPlayPlaylist!('favorites');
                          },
                          icon: const Icon(Icons.play_arrow_rounded, size: 16, color: Color(0xFFFF2D55)),
                          label: const Text('Play Favorites', style: TextStyle(color: Color(0xFFFF2D55), fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  if (_favorites.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'No favorite videos yet. Tap the heart icon in the feed to add favorites.',
                        style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13, fontStyle: FontStyle.italic),
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _favorites.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final path = _favorites[index];
                        final name = p.basename(path);
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.favorite_rounded, color: Color(0xFFFF2D55), size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  name,
                                  style: const TextStyle(color: Colors.white, fontSize: 13),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close_rounded, color: Colors.white38, size: 18),
                                onPressed: () => _removeFavorite(index),
                              ),
                            ],
                          ),
                        );
                      },
                    ),

                  const SizedBox(height: 24),

                  // Folder Sources Section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'SOURCE FOLDERS',
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _addFolder,
                        icon: const Icon(Icons.add_rounded, size: 16, color: Color(0xFF00F2FE)),
                        label: const Text('Add Folder', style: TextStyle(color: Color(0xFF00F2FE), fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  
                  if (_folders.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'No local folders selected yet. Add a folder to scan for videos.',
                        style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13, fontStyle: FontStyle.italic),
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _folders.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final path = _folders[index];
                        final displayName = path.split(Platform.pathSeparator).last;
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.folder_open_rounded, color: Colors.amber, size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      displayName.isNotEmpty ? displayName : path,
                                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      path,
                                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                                onPressed: () => _removeFolder(index),
                              ),
                            ],
                          ),
                        );
                      },
                    ),

                  const SizedBox(height: 24),

                  // File Sources Section (Upload / Fallback)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'UPLOAD / INDIVIDUAL VIDEOS',
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _addFiles,
                        icon: const Icon(Icons.file_upload_outlined, size: 16, color: Color(0xFF00F2FE)),
                        label: const Text('Upload Videos', style: TextStyle(color: Color(0xFF00F2FE), fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),

                  if (_files.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'No individual video files uploaded yet.',
                        style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13, fontStyle: FontStyle.italic),
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _files.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final path = _files[index];
                        final displayName = path.split(Platform.pathSeparator).last;
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.movie_outlined, color: Color(0xFF00F2FE), size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      displayName,
                                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      path,
                                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                                onPressed: () => _removeFile(index),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, {Color? accentColor}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            color: accentColor ?? Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 8.5,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}
