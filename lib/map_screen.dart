import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'auth_screen.dart';

class CTGMapScreen extends StatefulWidget {
  const CTGMapScreen({super.key});

  @override
  State<CTGMapScreen> createState() => _CTGMapScreenState();
}

class _CTGMapScreenState extends State<CTGMapScreen> {
  // Use 127.0.0.1 for Chrome, 10.0.2.2 for Android Emulator, or local machine Wi-Fi IP for phone
 static const String httpBaseUrl = 'https://ctg-shield-backend.onrender.com';
 static const String wsBaseUrl = 'wss://ctg-shield-backend.onrender.com';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  // Active User Profile from Secure Storage
  String _userId = "user_0";
  String _userName = "Citizen";
  String _userPhone = "N/A";
  String _emergencyContact = "N/A";

  LatLng currentLocation = const LatLng(22.3569, 91.8215); // GEC Circle
  final MapController _mapController = MapController();

  bool isLoading = false;
  bool isTrackingEnabled = false;
  StreamSubscription<Position>? _positionStreamSubscription;

  Map<String, dynamic>? safetyData;
  List<dynamic> incidentMarkersList = [];
  WebSocketChannel? _wsChannel;

  // Audio Player for Siren Alarm
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isSirenPlaying = false;
  static const String sirenAudioUrl =
      'https://assets.mixkit.co/active_storage/sfx/2869/2869-preview.mp3';

  @override
  void initState() {
    super.initState();
    _loadUserProfileAndConnect();
    evaluateLocationSafety(currentLocation.latitude, currentLocation.longitude);
    fetchRecentIncidents();
  }

  @override
  void dispose() {
    _stopSiren();
    _audioPlayer.dispose();
    _positionStreamSubscription?.cancel();
    _wsChannel?.sink.close();
    super.dispose();
  }

  Future<void> _loadUserProfileAndConnect() async {
    final id = await _storage.read(key: 'user_id');
    final name = await _storage.read(key: 'user_name');
    final phone = await _storage.read(key: 'user_phone');
    final contact = await _storage.read(key: 'emergency_contact');

    if (mounted) {
      setState(() {
        if (id != null) _userId = id;
        if (name != null) _userName = name;
        if (phone != null) _userPhone = phone;
        if (contact != null) _emergencyContact = contact;
      });
    }

    _initWebSocket();
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text("Sign Out", style: TextStyle(color: Colors.white)),
        content: const Text(
          "Are you sure you want to log out of CTG Shield?",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel", style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Sign Out", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _storage.deleteAll();
      _stopSiren();
      await _positionStreamSubscription?.cancel();
      _wsChannel?.sink.close();

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const AuthScreen()),
      );
    }
  }

  Future<void> _playSiren() async {
    try {
      if (!_isSirenPlaying) {
        await _audioPlayer.setReleaseMode(ReleaseMode.loop);
        await _audioPlayer.play(UrlSource(sirenAudioUrl));
        setState(() {
          _isSirenPlaying = true;
        });
      }
    } catch (e) {
      debugPrint("Audio playback error: $e");
    }
  }

  Future<void> _stopSiren() async {
    try {
      await _audioPlayer.stop();
      setState(() {
        _isSirenPlaying = false;
      });
    } catch (e) {
      debugPrint("Audio stop error: $e");
    }
  }

  void _initWebSocket() {
    try {
      _wsChannel = WebSocketChannel.connect(
        Uri.parse('$wsBaseUrl/ws/safety-stream/$_userId'),
      );
      _wsChannel!.stream.listen((message) {
        final alert = json.decode(message);
        _triggerEmergencySOSOverride(alert);
        fetchRecentIncidents();
      }, onError: (err) {
        debugPrint("WebSocket error: $err");
      });
    } catch (e) {
      debugPrint("Could not open WebSocket: $e");
    }
  }

  void _triggerEmergencySOSOverride(Map<String, dynamic> alert) {
    _playSiren();

    final victimName = alert['victim_name'] ?? alert['name'] ?? 'Citizen in Distress';
    final emergencyType = alert['emergency_type'] ?? 'PHYSICAL ATTACK';
    final victimPhone = alert['victim_phone'] ?? alert['contact'] ?? '+880 1819-000000';
    final emergencyGuardian = alert['emergency_contact'] ?? 'Not Specified';
    final victimLat = (alert['latitude'] as num?)?.toDouble() ?? currentLocation.latitude;
    final victimLon = (alert['longitude'] as num?)?.toDouble() ?? currentLocation.longitude;

    final distanceMeters = Geolocator.distanceBetween(
      currentLocation.latitude,
      currentLocation.longitude,
      victimLat,
      victimLon,
    );

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.85),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (ctx, anim1, anim2) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.redAccent, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withOpacity(0.5),
                    blurRadius: 28,
                    spreadRadius: 6,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.25),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.redAccent,
                      size: 60,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "🚨 HIGH PRIORITY SOS BROADCAST",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      children: [
                        _buildOverrideInfoRow("Victim:", victimName, Colors.white),
                        const SizedBox(height: 8),
                        _buildOverrideInfoRow("Incident:", emergencyType, Colors.amberAccent),
                        const SizedBox(height: 8),
                        _buildOverrideInfoRow("Victim Phone:", victimPhone, Colors.cyanAccent),
                        const SizedBox(height: 8),
                        _buildOverrideInfoRow("Guardian Phone:", emergencyGuardian, Colors.orangeAccent),
                        const SizedBox(height: 8),
                        _buildOverrideInfoRow(
                          "Proximity:",
                          "${distanceMeters.toStringAsFixed(0)} meters away",
                          Colors.greenAccent,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.white38),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () {
                            _stopSiren();
                            Navigator.pop(ctx);
                          },
                          child: const Text(
                            "Dismiss Siren",
                            style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.navigation_rounded, color: Colors.white),
                          label: const Text(
                            "Center Victim",
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                          onPressed: () {
                            _stopSiren();
                            Navigator.pop(ctx);
                            final victimPoint = LatLng(victimLat, victimLon);
                            _mapController.move(victimPoint, 16.5);
                            evaluateLocationSafety(victimLat, victimLon);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildOverrideInfoRow(String label, String value, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 13)),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(color: valueColor, fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Future<bool> _handleLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.amber,
            content: Text('Location services are disabled. Please enable device GPS.'),
          ),
        );
      }
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.red,
              content: Text('Location permissions are denied.'),
            ),
          );
        }
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.red,
            content: Text('Location permissions permanently denied.'),
          ),
        );
      }
      return false;
    }
    return true;
  }

  Future<void> _toggleLiveTracking() async {
    if (isTrackingEnabled) {
      await _positionStreamSubscription?.cancel();
      _positionStreamSubscription = null;
      setState(() {
        isTrackingEnabled = false;
      });
    } else {
      final hasPermission = await _handleLocationPermission();
      if (!hasPermission) return;

      setState(() {
        isTrackingEnabled = true;
      });

      try {
        Position initialPos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        _onLocationChanged(initialPos);
      } catch (e) {
        debugPrint("Initial GPS lock error: $e");
      }

      const locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      );

      _positionStreamSubscription = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        (Position position) => _onLocationChanged(position),
        onError: (err) => debugPrint("GPS stream error: $err"),
      );
    }
  }

  void _onLocationChanged(Position position) {
    final updatedPoint = LatLng(position.latitude, position.longitude);
    setState(() {
      currentLocation = updatedPoint;
    });

    _mapController.move(updatedPoint, 15.5);
    evaluateLocationSafety(position.latitude, position.longitude);

    if (_wsChannel != null) {
      try {
        _wsChannel!.sink.add(json.encode({
          "lon": position.longitude,
          "lat": position.latitude,
        }));
      } catch (e) {
        debugPrint("WS send error: $e");
      }
    }
  }

  Future<void> fetchRecentIncidents() async {
    final url = Uri.parse('$httpBaseUrl/api/v1/incidents/recent?limit=50');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final List<dynamic> list = json.decode(response.body);
        setState(() {
          incidentMarkersList = list;
        });
      }
    } catch (e) {
      debugPrint("Failed to fetch incidents: $e");
    }
  }

  Future<void> evaluateLocationSafety(double lat, double lon) async {
    setState(() {
      isLoading = true;
    });

    final url = Uri.parse('$httpBaseUrl/api/v1/safety/evaluate-location?lon=$lon&lat=$lat');

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        setState(() {
          safetyData = decoded;
          isLoading = false;
        });
      } else {
        setState(() {
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        isLoading = false;
      });
    }
  }

  IconData _getIncidentIcon(String type) {
    switch (type.toUpperCase()) {
      case 'MUGGING':
      case 'SNATCHING':
        return Icons.person_remove_rounded;
      case 'ROBBERY':
        return Icons.dangerous_rounded;
      case 'HARASSMENT':
        return Icons.record_voice_over_rounded;
      case 'HAZARD':
        return Icons.construction_rounded;
      case 'ASSAULT':
        return Icons.local_police_rounded;
      default:
        return Icons.report_problem_rounded;
    }
  }

  Color _getIncidentColor(String type) {
    switch (type.toUpperCase()) {
      case 'MUGGING':
      case 'SNATCHING':
        return Colors.redAccent;
      case 'ROBBERY':
        return Colors.deepOrangeAccent;
      case 'HARASSMENT':
        return Colors.purpleAccent;
      case 'HAZARD':
        return Colors.amberAccent;
      case 'ASSAULT':
        return Colors.red.shade900;
      default:
        return Colors.blueGrey;
    }
  }

  Color _getRiskColor(String? riskTag) {
    switch (riskTag) {
      case 'HIGH':
        return Colors.redAccent;
      case 'MEDIUM':
        return Colors.orangeAccent;
      case 'LOW':
      default:
        return Colors.greenAccent;
    }
  }

  void _showIncidentInfoModal(Map<String, dynamic> incident) {
    final type = incident['incident_type'] ?? 'INCIDENT';
    final desc = incident['description'] ?? 'No description provided';
    final time = incident['created_at'] != null
        ? incident['created_at'].toString().replaceFirst('T', ' ').substring(0, 16)
        : 'Recently';

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_getIncidentIcon(type), color: _getIncidentColor(type), size: 28),
                const SizedBox(width: 10),
                Text(
                  type,
                  style: TextStyle(
                    color: _getIncidentColor(type),
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(desc, style: const TextStyle(color: Colors.white, fontSize: 16)),
            const SizedBox(height: 8),
            Text("Reported: $time (UTC)", style: const TextStyle(color: Colors.white60, fontSize: 13)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF334155)),
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Close", style: TextStyle(color: Colors.white)),
              ),
            )
          ],
        ),
      ),
    );
  }

  List<Marker> _buildAllMarkers() {
    List<Marker> markers = [];

    for (var inc in incidentMarkersList) {
      if (inc['latitude'] != null && inc['longitude'] != null) {
        final lat = (inc['latitude'] as num).toDouble();
        final lon = (inc['longitude'] as num).toDouble();
        final type = inc['incident_type'] ?? 'INCIDENT';
        final color = _getIncidentColor(type);
        final iconData = _getIncidentIcon(type);

        markers.add(
          Marker(
            point: LatLng(lat, lon),
            width: 38,
            height: 38,
            child: GestureDetector(
              onTap: () => _showIncidentInfoModal(inc),
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.4),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(iconData, color: Colors.white, size: 20),
              ),
            ),
          ),
        );
      }
    }

    markers.add(
      Marker(
        point: currentLocation,
        width: 52,
        height: 52,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isTrackingEnabled
                    ? Colors.cyanAccent.withOpacity(0.25)
                    : Colors.blueAccent.withOpacity(0.20),
              ),
            ),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isTrackingEnabled ? Colors.cyanAccent : Colors.blueAccent,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return markers;
  }

  void _showReportIncidentDialog() {
    String selectedType = "MUGGING";
    final TextEditingController descController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text("Report Incident at Pin", style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: selectedType,
                dropdownColor: const Color(0xFF0F172A),
                decoration: const InputDecoration(
                  labelText: "Incident Type",
                  labelStyle: TextStyle(color: Colors.white70),
                ),
                items: const [
                  DropdownMenuItem(value: "MUGGING", child: Text("Mugging / Snatching", style: TextStyle(color: Colors.white))),
                  DropdownMenuItem(value: "HARASSMENT", child: Text("Harassment", style: TextStyle(color: Colors.white))),
                  DropdownMenuItem(value: "ROBBERY", child: Text("Robbery", style: TextStyle(color: Colors.white))),
                  DropdownMenuItem(value: "HAZARD", child: Text("Road / Civic Hazard", style: TextStyle(color: Colors.white))),
                ],
                onChanged: (val) => setModalState(() => selectedType = val!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: "Description",
                  labelStyle: TextStyle(color: Colors.white70),
                  hintText: "e.g., Bag snatched by bike riders",
                  hintStyle: TextStyle(color: Colors.white38),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel", style: TextStyle(color: Colors.white60)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
              onPressed: () async {
                final url = Uri.parse('$httpBaseUrl/api/v1/incidents/report');
                try {
                  final res = await http.post(
                    url,
                    headers: {"Content-Type": "application/json"},
                    body: json.encode({
                      "incident_type": selectedType,
                      "description": descController.text.isNotEmpty
                          ? descController.text
                          : "Reported by $_userName",
                      "longitude": currentLocation.longitude,
                      "latitude": currentLocation.latitude,
                    }),
                  );

                  if (mounted) {
                    Navigator.pop(ctx);
                    if (res.statusCode == 200) {
                      await fetchRecentIncidents();
                      evaluateLocationSafety(currentLocation.latitude, currentLocation.longitude);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          backgroundColor: Colors.green,
                          content: Text("Incident saved and added to live map!"),
                        ),
                      );
                    }
                  }
                } catch (e) {
                  if (mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(backgroundColor: Colors.red, content: Text("Error: $e")),
                    );
                  }
                }
              },
              child: const Text("Submit", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _triggerSOS() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text("⚠️ TRIGGER EMERGENCY SOS?", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
        content: Text(
          "Broadcasting emergency alert as $_userName ($_userPhone). Guardian Contact ($_emergencyContact) will be notified.",
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("CANCEL", style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("SEND SOS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final url = Uri.parse('$httpBaseUrl/api/v1/sos/trigger');
    final payload = {
      "user_id": _userId,
      "user_name": _userName,
      "user_phone": _userPhone,
      "emergency_contact": _emergencyContact,
      "longitude": currentLocation.longitude,
      "latitude": currentLocation.latitude,
      "emergency_type": "PHYSICAL ATTACK",
      "broadcast_radius_meters": 2500.0,
    };

    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: json.encode(payload),
      );

      if (response.statusCode == 200) {
        if (!mounted) return;
        await fetchRecentIncidents();

        // Launch full-screen override modal and siren directly
        _triggerEmergencySOSOverride({
          "victim_name": "You ($_userName)",
          "emergency_type": "PHYSICAL ATTACK",
          "victim_phone": _userPhone,
          "emergency_contact": _emergencyContact,
          "latitude": currentLocation.latitude,
          "longitude": currentLocation.longitude,
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to send SOS: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final riskTag = safetyData?['risk_level_tag'] ?? 'LOW';
    final dangerColor = _getRiskColor(riskTag);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('CTG Shield Radar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text('Active User: $_userName', style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
          ],
        ),
        backgroundColor: const Color(0xFF1E293B),
        actions: [
          // 1. Red Emergency Siren Broadcast Simulator Icon
          IconButton(
            icon: const Icon(Icons.emergency_share, color: Colors.redAccent),
            tooltip: "Test Incoming SOS Broadcast",
            onPressed: () {
              _triggerEmergencySOSOverride({
                "victim_name": "Rashed Karim (Nearby Citizen)",
                "emergency_type": "MUGGING IN PROGRESS",
                "victim_phone": "+880 1711-223344",
                "emergency_contact": "+880 1819-001122",
                "latitude": 22.3578,
                "longitude": 91.8385,
              });
            },
          ),
          // 2. Refresh Button
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            tooltip: "Refresh Markers",
            onPressed: () {
              fetchRecentIncidents();
              evaluateLocationSafety(currentLocation.latitude, currentLocation.longitude);
            },
          ),
          // 3. Report Pin Button
          IconButton(
            icon: const Icon(Icons.add_location_alt_outlined, color: Colors.blueAccent),
            tooltip: "Report Incident",
            onPressed: _showReportIncidentDialog,
          ),
          // 4. Logout Button
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.white60),
            tooltip: "Sign Out",
            onPressed: _logout,
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: currentLocation,
              initialZoom: 14.5,
              onTap: (tapPosition, point) {
                if (!isTrackingEnabled) {
                  setState(() => currentLocation = point);
                  evaluateLocationSafety(point.latitude, point.longitude);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.ctgshield.mobile',
              ),
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: const LatLng(22.3569, 91.8215), // GEC Circle
                    color: Colors.red.withOpacity(0.22),
                    borderColor: Colors.red,
                    borderStrokeWidth: 2,
                    useRadiusInMeter: true,
                    radius: 600,
                  ),
                  CircleMarker(
                    point: const LatLng(22.3685, 91.8229), // 2 No Gate
                    color: Colors.orange.withOpacity(0.22),
                    borderColor: Colors.orange,
                    borderStrokeWidth: 2,
                    useRadiusInMeter: true,
                    radius: 500,
                  ),
                  CircleMarker(
                    point: const LatLng(22.3275, 91.8122), // Agrabad
                    color: Colors.amber.withOpacity(0.22),
                    borderColor: Colors.amber,
                    borderStrokeWidth: 2,
                    useRadiusInMeter: true,
                    radius: 800,
                  ),
                  CircleMarker(
                    point: const LatLng(22.3578, 91.8385), // Chawkbazar
                    color: Colors.orange.withOpacity(0.22),
                    borderColor: Colors.orange,
                    borderStrokeWidth: 2,
                    useRadiusInMeter: true,
                    radius: 600,
                  ),
                ],
              ),
              MarkerLayer(
                markers: _buildAllMarkers(),
              ),
            ],
          ),

          // Floating GPS Control Button
          Positioned(
            right: 16,
            top: 16,
            child: FloatingActionButton.extended(
              backgroundColor: isTrackingEnabled ? Colors.teal : const Color(0xFF1E293B),
              foregroundColor: Colors.white,
              icon: Icon(
                isTrackingEnabled ? Icons.gps_fixed : Icons.gps_not_fixed,
                color: isTrackingEnabled ? Colors.cyanAccent : Colors.white70,
              ),
              label: Text(
                isTrackingEnabled ? "GPS Active" : "Track GPS",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: _toggleLiveTracking,
            ),
          ),

          // Bottom Floating Info Card
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Card(
              elevation: 10,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              color: const Color(0xFF0F172A).withOpacity(0.94),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.shield, color: dangerColor, size: 26),
                            const SizedBox(width: 8),
                            Text("Risk Level: $riskTag", style: TextStyle(color: dangerColor, fontWeight: FontWeight.bold, fontSize: 17)),
                          ],
                        ),
                        if (isLoading)
                          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Score: ${safetyData?['danger_score'] ?? 0}/100", style: const TextStyle(color: Colors.white, fontSize: 13)),
                        Text("Live Pins: ${incidentMarkersList.length}", style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                        Text("Hotspot: ${safetyData?['is_in_active_risk_zone'] == true ? 'YES' : 'NO'}", style: TextStyle(color: safetyData?['is_in_active_risk_zone'] == true ? Colors.redAccent : Colors.greenAccent, fontSize: 13, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const Divider(color: Colors.white24, height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.blueAccent)),
                            icon: const Icon(Icons.add_alert, color: Colors.blueAccent, size: 18),
                            label: const Text("Report Incident", style: TextStyle(color: Colors.blueAccent)),
                            onPressed: _showReportIncidentDialog,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                            icon: const Icon(Icons.sos, color: Colors.white, size: 20),
                            label: const Text("SEND SOS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            onPressed: _triggerSOS,
                          ),
                        ),
                      ],
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
}