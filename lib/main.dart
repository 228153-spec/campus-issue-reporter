import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase init failed: $e'); // app still works offline
  }
  runApp(const TasteTrailApp());
}

// ───────────────────────── Model ─────────────────────────
class Memory {
  final String id;
  final String dish;
  final String note;
  final int rating;
  final String imagePath;
  final double? lat;
  final double? lng;
  final DateTime time;
  bool synced;

  Memory({
    required this.id,
    required this.dish,
    required this.note,
    required this.rating,
    required this.imagePath,
    required this.time,
    this.lat,
    this.lng,
    this.synced = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'dish': dish,
        'note': note,
        'rating': rating,
        'imagePath': imagePath,
        'lat': lat,
        'lng': lng,
        'time': time.toIso8601String(),
        'synced': synced,
      };

  factory Memory.fromJson(Map<String, dynamic> j) => Memory(
        id: j['id'],
        dish: j['dish'],
        note: j['note'] ?? '',
        rating: j['rating'] ?? 0,
        imagePath: j['imagePath'],
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        time: DateTime.parse(j['time']),
        synced: j['synced'] ?? false,
      );
}

// ───────────────────────── App ─────────────────────────
class TasteTrailApp extends StatelessWidget {
  const TasteTrailApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TasteTrail',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFF7043)),
        scaffoldBackgroundColor: const Color(0xFFFFF8F3),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _prefsKey = 'tastetrail_memories';

  final _dishCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  List<Memory> _memories = [];
  int _rating = 4;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadFromPrefs(); // restores last photo + GPS after a full restart
  }

  @override
  void dispose() {
    _dishCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  // ───────── Local caching (SharedPreferences) ─────────
  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      final list = (jsonDecode(raw) as List)
          .map((e) => Memory.fromJson(e as Map<String, dynamic>))
          .where((m) => File(m.imagePath).existsSync())
          .toList();
      if (mounted) setState(() => _memories = list);
    }
    _syncPending();
  }

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _prefsKey, jsonEncode(_memories.map((m) => m.toJson()).toList()));
  }

  // ───────── Permissions + sensors ─────────
  Future<bool> _ensureCameraPermission() async {
    var status = await Permission.camera.request();
    if (status.isGranted) return true;
    _snack(
      'Camera permission is needed to snap your food.',
      action: status.isPermanentlyDenied
          ? SnackBarAction(label: 'Settings', onPressed: openAppSettings)
          : null,
    );
    return false;
  }

  /// Returns null when location is unavailable. Never throws, never crashes.
  Future<Position?> _getLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _snack('Location service is off. Saved without GPS.',
            action: SnackBarAction(
                label: 'Turn on', onPressed: Geolocator.openLocationSettings));
        return null;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied) {
        _snack('Location denied. Memory saved without GPS.');
        return null;
      }
      if (perm == LocationPermission.deniedForever) {
        _snack('Location permanently denied. Enable it in Settings.',
            action: SnackBarAction(
                label: 'Settings', onPressed: Geolocator.openAppSettings));
        return null;
      }
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (e) {
      _snack('Could not get location. Saved without GPS.');
      return null;
    }
  }

  // ───────── Main action ─────────
  Future<void> _capture() async {
    if (_dishCtrl.text.trim().isEmpty) {
      _snack('Give your dish a name first 🍜');
      return;
    }
    if (!await _ensureCameraPermission()) return;

    final shot = await ImagePicker()
        .pickImage(source: ImageSource.camera, imageQuality: 70);
    if (shot == null) return;

    setState(() => _busy = true);
    try {
      final pos = await _getLocation();

      // Copy photo to permanent storage (camera cache can be cleared)
      final dir = await getApplicationDocumentsDirectory();
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      final saved = await File(shot.path).copy(p.join(dir.path, '$id.jpg'));

      final memory = Memory(
        id: id,
        dish: _dishCtrl.text.trim(),
        note: _noteCtrl.text.trim(),
        rating: _rating,
        imagePath: saved.path,
        lat: pos?.latitude,
        lng: pos?.longitude,
        time: DateTime.now(),
      );

      // 1) save locally FIRST
      setState(() => _memories.insert(0, memory));
      await _saveToPrefs();
      _dishCtrl.clear();
      _noteCtrl.clear();
      _snack('Saved to your trail ✅');

      // 2) then push to the cloud (may fail offline, retried later)
      _syncPending();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ───────── Cloud sync (Firestore) ─────────
  Future<void> _syncPending() async {
    for (final m in _memories.where((m) => !m.synced)) {
      try {
        await FirebaseFirestore.instance
            .collection('tastetrail')
            .doc(m.id) // same id = safe to retry, no duplicates
            .set({
          'dish': m.dish,
          'note': m.note,
          'rating': m.rating,
          'lat': m.lat,
          'lng': m.lng,
          'time': m.time.toIso8601String(),
        }).timeout(const Duration(seconds: 6));
        m.synced = true;
        await _saveToPrefs();
        if (mounted) setState(() {});
      } catch (_) {
        // offline: stays unsynced, retried next time the app opens
      }
    }
  }

  void _snack(String msg, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), action: action));
  }

  // ───────── UI ─────────
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(cs),
              const SizedBox(height: 16),
              _lastMemoryCard(cs),
              const SizedBox(height: 16),
              _formCard(cs),
              const SizedBox(height: 20),
              if (_memories.length > 1) ...[
                const Text('Earlier on your trail',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ..._memories.skip(1).map(_historyTile),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(ColorScheme cs) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFFFF7043), Color(0xFFFFB74D)]),
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Row(
        children: [
          Text('🍜', style: TextStyle(fontSize: 40)),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('TasteTrail',
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                Text('Leave a trail of every tasty stop',
                    style: TextStyle(color: Colors.white70)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _lastMemoryCard(ColorScheme cs) {
    if (_memories.isEmpty) {
      return Container(
        width: double.infinity,
        height: 180,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cs.primary.withOpacity(0.3)),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.restaurant_menu, size: 48, color: Colors.grey),
            SizedBox(height: 8),
            Text('No food memories yet.\nSnap your first bite!',
                textAlign: TextAlign.center),
          ],
        ),
      );
    }
    final m = _memories.first;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
            child: Image.file(
              File(m.imagePath),
              width: double.infinity,
              height: 220,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                  height: 220,
                  color: Colors.grey.shade200,
                  child: const Icon(Icons.broken_image)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(m.dish,
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold)),
                    ),
                    Icon(m.synced ? Icons.cloud_done : Icons.cloud_off,
                        color: m.synced ? Colors.green : Colors.orange,
                        size: 20),
                  ],
                ),
                Row(
                  children: List.generate(
                      5,
                      (i) => Icon(i < m.rating ? Icons.star : Icons.star_border,
                          color: Colors.amber, size: 20)),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.location_on, size: 18, color: Colors.red),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        m.lat != null
                            ? 'Lat ${m.lat!.toStringAsFixed(5)}, Lng ${m.lng!.toStringAsFixed(5)}'
                            : 'Location unavailable',
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    ),
                  ],
                ),
                if (m.note.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(m.note),
                ],
                const SizedBox(height: 6),
                Text(
                  m.synced ? 'Synced to cloud' : 'Saved on device, waiting to sync',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _formCard(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('New food memory',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          TextField(
            controller: _dishCtrl,
            decoration: const InputDecoration(
                labelText: 'What did you eat?',
                prefixIcon: Icon(Icons.ramen_dining),
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Rating'),
              const Spacer(),
              ...List.generate(
                5,
                (i) => GestureDetector(
                  onTap: () => setState(() => _rating = i + 1),
                  child: Icon(i < _rating ? Icons.star : Icons.star_border,
                      color: Colors.amber, size: 32),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
                labelText: 'Note (optional)',
                prefixIcon: Icon(Icons.edit_note),
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _busy ? null : _capture,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.camera_alt),
              label: Text(_busy ? 'Saving…' : 'Snap & Tag Location'),
              style: ElevatedButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyTile(Memory m) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(File(m.imagePath),
                width: 60,
                height: 60,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const SizedBox(width: 60, height: 60, child: Icon(Icons.image))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.dish,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(
                  m.lat != null
                      ? '${m.lat!.toStringAsFixed(4)}, ${m.lng!.toStringAsFixed(4)}'
                      : 'No GPS',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          Row(children: [
            const Icon(Icons.star, color: Colors.amber, size: 18),
            Text('${m.rating}'),
          ]),
        ],
      ),
    );
  }
}
