import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:opencv_eye/main/frontend/clickhere.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:camera/camera.dart';
import 'dart:async';
import 'dart:math';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  ModelHandler _modelHandler = ModelHandler();
  bool _isMonitoring = false;
  String _alertnessLevel = 'Alert';
  double _alertnessScore = 85.0;
  int _sessionTime = 0;
  Timer? _sessionTimer;
  late AnimationController _pulseController;
  late AnimationController _waveController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _waveAnimation;
  String? _username = 'User';
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  final List<Map<String, dynamic>> _recentSessions = [
    {'date': 'Today', 'duration': '2h 15m', 'alertness': 92, 'status': 'Excellent'},
    {'date': 'Yesterday', 'duration': '1h 45m', 'alertness': 78, 'status': 'Good'},
    {'date': '2 days ago', 'duration': '3h 30m', 'alertness': 65, 'status': 'Fair'},
  ];

  @override
  void initState() {
    super.initState();
    _fetchUsername();
    _initializeCamera();
    _pulseController = AnimationController(
      duration: Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    
    _waveController = AnimationController(
      duration: Duration(seconds: 3),
      vsync: this,
    )..repeat();

    _pulseAnimation = Tween<double>(
      begin: 0.8,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    _waveAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(_waveController);
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        _cameraController = CameraController(
          _cameras![0],
          ResolutionPreset.medium,
        );
        await _cameraController!.initialize();
        setState(() {
          _isCameraInitialized = true;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No camera available on this device.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to initialize camera: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _fetchUsername() async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user != null) {
        final fullName = user.userMetadata?['full_name'] as String?;
        setState(() {
          _username = fullName ?? 'User';
        });
      }
    } catch (error) {
      setState(() {
        _username = 'User';
      });
    }
  }
Float32List preprocessCameraImage(CameraImage cameraImage) {
  // Convert YUV420 to grayscale using Y channel
  final yPlane = cameraImage.planes[0].bytes;
  img.Image grayscale = img.Image(width: cameraImage.width, height: cameraImage.height);

  for (var y = 0; y < cameraImage.height; y++) {
    for (var x = 0; x < cameraImage.width; x++) {
      final yIndex = y * cameraImage.width + x;
      grayscale.setPixelRgb(x, y, yPlane[yIndex], yPlane[yIndex], yPlane[yIndex]);
    }
  }

  // Resize to 100x100
  img.Image resized = img.copyResize(grayscale, width: 100, height: 100);

  // Convert to Float32List and normalize to [0, 1]
  var input = Float32List(100 * 100);
  int pixelIndex = 0;
  for (var y = 0; y < 100; y++) {
    for (var x = 0; x < 100; x++) {
      var pixel = resized.getPixel(x, y);
      input[pixelIndex++] = (pixel.r / 127.5) - 1.0; // Normalize to [-1, 1] // Grayscale value normalized
    }
  }

  return input;
}
  Future<void> _logout() async {
    try {
      final supabase = Supabase.instance.client;
      await supabase.auth.signOut();
      Navigator.of(context).pushReplacementNamed('/login');
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error logging out: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    _pulseController.dispose();
    _waveController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  void _toggleMonitoring() {
    setState(() {
      _isMonitoring = !_isMonitoring;
      if (_isMonitoring) {
        _startSession();
      } else {
        _stopSession();
      }
    });
  }

  void _startSession() {
  if (!_isCameraInitialized || _cameraController == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Camera not initialized. Please try again.'),
        backgroundColor: Colors.red,
      ),
    );
    setState(() {
      _isMonitoring = false;
    });
    return;
  }

  _sessionTime = 0;
  _sessionTimer = Timer.periodic(Duration(seconds: 1), (timer) {
    setState(() {
      _sessionTime++;
    });
  });

  // Initialize ModelHandler
  _modelHandler.loadModel().then((_) {
    // Start camera image stream
    int frameCount = 0; // For frame skipping
    _cameraController!.startImageStream((CameraImage cameraImage) async {
      if (!_isMonitoring) return; // Stop processing if monitoring is off
      if (frameCount % 5 != 0) { // Process every 5th frame for performance
        frameCount++;
        return;
      }
      frameCount++;

      // Log camera details for debugging
      print('Camera format: ${cameraImage.format.group}, ${cameraImage.width}x${cameraImage.height}');

      // Preprocess image to 100x100 grayscale
      var inputTensor = preprocessCameraImage(cameraImage).reshape([1, 100, 100, 1]);

      // Prepare output tensor for single value
      var outputTensor = Float32List(1).reshape([1, 1]);

      // Run inference
      try {
        _modelHandler.interpreter!.run(inputTensor, outputTensor);
        // Update alertness score based on model output
        setState(() {
          _alertnessScore = outputTensor[0][0]; // Use raw output if not a probability; // Scale to 0-100
          if (_alertnessScore > 80) {
            _alertnessLevel = 'Alert';
          } else if (_alertnessScore > 60) {
            _alertnessLevel = 'Moderate';
          } else {
            _alertnessLevel = 'Drowsy';
          }
        });
        print('Model output: $outputTensor');
      } catch (e) {
        print('Inference error: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Inference failed: $e')),
        );
      }
    });
  });
}
 void _stopSession() {
  _sessionTimer?.cancel();
  if (_cameraController != null && _cameraController!.value.isStreamingImages) {
    _cameraController!.stopImageStream();
  }
}

  String _formatTime(int seconds) {
    int hours = seconds ~/ 3600;
    int minutes = (seconds % 3600) ~/ 60;
    int secs = seconds % 60;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  Color _getAlertnessColor() {
    if (_alertnessScore > 80) return Colors.green;
    if (_alertnessScore > 60) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      endDrawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF6C63FF),
                    Color(0xFF4FACFE),
                  ],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Settings',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    _username ?? 'User',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: Icon(Icons.gamepad, color: Color(0xFF6C63FF)),
              title: Text('Flappy Bird', style: TextStyle(fontSize: 16)),
              onTap: () {
                Navigator.of(context).pushNamed('/flappybird');
              },
            ),
            ListTile(
              leading: Icon(Icons.logout, color: Colors.red),
              title: Text('Log Out', style: TextStyle(fontSize: 16)),
              onTap: () async {
                await _logout();
              },
            ),
          ],
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF8B5FBF),
              Color(0xFF6C63FF),
              Color(0xFF4FACFE),
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Good morning,',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.white.withOpacity(0.8),
                          ),
                        ),
                        Text(
                          _username ?? 'User',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    GestureDetector(
                      onTap: () {
                        _scaffoldKey.currentState?.openEndDrawer();
                      },
                      child: Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          Icons.settings,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 32),
                Container(
                  padding: EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 20,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Text(
                        _isMonitoring ? 'Monitoring Active' : 'Ready to Monitor',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2D3748),
                        ),
                      ),
                      SizedBox(height: 24),
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          if (_isMonitoring && _isCameraInitialized && _cameraController != null) ...[
                            Container(
                              width: 200,
                              height: 200,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _getAlertnessColor(),
                                  width: 3,
                                ),
                              ),
                              child: ClipOval(
                                child: CameraPreview(_cameraController!),
                              ),
                            ),
                          ] else ...[
                            AnimatedBuilder(
                              animation: _waveAnimation,
                              builder: (context, child) {
                                return Container(
                                  width: 200 + (sin(_waveAnimation.value * 2 * pi) * 20),
                                  height: 200 + (sin(_waveAnimation.value * 2 * pi) * 20),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: _getAlertnessColor().withOpacity(0.3),
                                      width: 2,
                                    ),
                                  ),
                                );
                              },
                            ),
                            AnimatedBuilder(
                              animation: _isMonitoring ? _pulseAnimation : _pulseController,
                              builder: (context, child) {
                                return Transform.scale(
                                  scale: _isMonitoring ? _pulseAnimation.value : 1.0,
                                  child: Container(
                                    width: 150,
                                    height: 150,
                                    decoration: BoxDecoration(
                                      color: _isMonitoring 
                                          ? _getAlertnessColor().withOpacity(0.1)
                                          : Color(0xFF6C63FF).withOpacity(0.1),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: _isMonitoring ? _getAlertnessColor() : Color(0xFF6C63FF),
                                        width: 3,
                                      ),
                                    ),
                                    child: Icon(
                                      _isMonitoring ? Icons.visibility : Icons.remove_red_eye_outlined,
                                      size: 60,
                                      color: _isMonitoring ? _getAlertnessColor() : Color(0xFF6C63FF),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                      SizedBox(height: 24),
                      if (_isMonitoring) ...[
                        Text(
                          _alertnessLevel,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: _getAlertnessColor(),
                          ),
                        ),
                        Text(
                          '${_alertnessScore.toInt()}% Alert',
                          style: TextStyle(
                            fontSize: 16,
                            color: Color(0xFF718096),
                          ),
                        ),
                        SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          height: 8,
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: FractionallySizedBox(
                            widthFactor: _alertnessScore / 100,
                            alignment: Alignment.centerLeft,
                            child: Container(
                              decoration: BoxDecoration(
                                color: _getAlertnessColor(),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: 24),
                        Text(
                          'Session Time',
                          style: TextStyle(
                            fontSize: 14,
                            color: Color(0xFF718096),
                          ),
                        ),
                        Text(
                          _formatTime(_sessionTime),
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2D3748),
                          ),
                        ),
                      ],
                      SizedBox(height: 32),
                      Column(
  children: [
    Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _isMonitoring
              ? [Colors.red, Colors.redAccent]
              : [Color(0xFF6C63FF), Color(0xFF4FACFE)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: (_isMonitoring ? Colors.red : Color(0xFF6C63FF)).withOpacity(0.3),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _toggleMonitoring,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(
          _isMonitoring ? 'Stop Monitoring' : 'Start Monitoring',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    ),
    const SizedBox(height: 16),
    ElevatedButton(
    onPressed: () {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (context) => const ClickHerePage()),
  );
},
      style: ElevatedButton.styleFrom(
        backgroundColor: Color(0xFF4FACFE),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        padding: EdgeInsets.symmetric(horizontal: 32, vertical: 14),
      ),
      child: const Text(
        'Click Here',
        style: TextStyle(
          fontSize: 16,
          color: Colors.white,
        ),
      ),
    ),
  ],
)

                    ],
                  ),
                ),
                SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.timeline,
                              color: Color(0xFF6C63FF),
                              size: 32,
                            ),
                            SizedBox(height: 12),
                            Text(
                              '12',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF2D3748),
                              ),
                            ),
                            Text(
                              'Sessions',
                              style: TextStyle(
                                fontSize: 14,
                                color: Color(0xFF718096),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Container(
                        padding: EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.access_time,
                              color: Color(0xFF4FACFE),
                              size: 32,
                            ),
                            SizedBox(height: 12),
                            Text(
                              '24h',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF2D3748),
                              ),
                            ),
                            Text(
                              'Total Time',
                              style: TextStyle(
                                fontSize: 14,
                                color: Color(0xFF718096),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 24),
                Container(
                  padding: EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Recent Sessions',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2D3748),
                            ),
                          ),
                          Text(
                            'View All',
                            style: TextStyle(
                              fontSize: 14,
                              color: Color(0xFF6C63FF),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 20),
                      ...List.generate(_recentSessions.length, (index) {
                        final session = _recentSessions[index];
                        return Container(
                          margin: EdgeInsets.only(bottom: 16),
                          padding: EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Color(0xFFF7FAFC),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: Color(0xFF6C63FF).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.visibility,
                                  color: Color(0xFF6C63FF),
                                  size: 24,
                                ),
                              ),
                              SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      session['date'],
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF2D3748),
                                      ),
                                    ),
                                    Text(
                                      session['duration'],
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Color(0xFF718096),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${session['alertness']}%',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: session['alertness'] > 80 
                                          ? Colors.green 
                                          : session['alertness'] > 60 
                                              ? Colors.orange 
                                              : Colors.red,
                                    ),
                                  ),
                                  Text(
                                    session['status'],
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF718096),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}