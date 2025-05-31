import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math';

class FlappyBirdPage extends StatefulWidget {
  const FlappyBirdPage({super.key});

  @override
  State<FlappyBirdPage> createState() => _FlappyBirdPageState();
}

class _FlappyBirdPageState extends State<FlappyBirdPage> with TickerProviderStateMixin {
  // Bird properties
  double _birdY = 0;
  double _birdVelocity = 0;

  // Game physics
  static const double _gravity = 0.4;
  static const double _jumpForce = -8.0;
  static const double _maxVelocity = 8.0;

  // Pipe properties
  List<Map<String, dynamic>> _pipes = [];
  static const double _pipeGap = 200.0;
  static const double _pipeWidth = 60.0;
  static const double _pipeSpeed = 2.0;

  // Game state
  bool _gameStarted = false;
  bool _gameOver = false;
  int _score = 0;
  int _bestScore = 0;

  // Animation and timing
  Timer? _gameTimer;
  late AnimationController _birdAnimationController;
  late Animation<double> _birdAnimation;

  // Bird visual constants
  static const double _birdSize = 20.0;
  static const double _birdX = 80.0;

  @override
  void initState() {
    super.initState();
    _birdAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _birdAnimation = Tween<double>(begin: -0.2, end: 0.2).animate(
      CurvedAnimation(parent: _birdAnimationController, curve: Curves.easeInOut),
    );
    _birdAnimationController.repeat(reverse: true);
  }

  void _initializeGame() {
    _birdY = 0;
    _birdVelocity = 0;
    _pipes.clear();
    _score = 0;
    _gameStarted = false;
    _gameOver = false;
  }

  void _generatePipe() {
    final random = Random();
    final screenHeight = MediaQuery.of(context).size.height;
    final gameHeight = screenHeight * 0.75;

    double minHeight = gameHeight * 0.15;
    double maxHeight = gameHeight * 0.6;
    double topPipeHeight = minHeight + random.nextDouble() * (maxHeight - minHeight);
    double bottomPipeHeight = gameHeight - topPipeHeight - _pipeGap;

    _pipes.add({
      'x': MediaQuery.of(context).size.width + 50,
      'topPipeHeight': topPipeHeight,
      'bottomPipeHeight': bottomPipeHeight,
      'isScored': false,
    });
  }

  void _startGame() {
    if (_gameOver) {
      _initializeGame();
    }

    _gameStarted = true;
    _generatePipe();

    _gameTimer = Timer.periodic(const Duration(milliseconds: 20), (_) => _updateGame());
  }

  void _updateGame() {
    setState(() {
      _birdVelocity += _gravity;
      _birdVelocity = _birdVelocity.clamp(-_maxVelocity, _maxVelocity);
      _birdY += _birdVelocity;

      for (int i = 0; i < _pipes.length; i++) {
        _pipes[i]['x'] -= _pipeSpeed;

        if (!_pipes[i]['isScored'] && _pipes[i]['x'] + _pipeWidth / 2 < _birdX) {
          _pipes[i]['isScored'] = true;
          _score++;
          _bestScore = max(_score, _bestScore);
        }
      }

      _pipes.removeWhere((pipe) => pipe['x'] < -_pipeWidth);
      if (_pipes.isEmpty || _pipes.last['x'] < MediaQuery.of(context).size.width - 200) {
        _generatePipe();
      }

      if (_checkCollision()) {
        _endGame();
      }
    });
  }

  bool _checkCollision() {
    final screenHeight = MediaQuery.of(context).size.height;
    final gameHeight = screenHeight * 0.75;
    final gameTop = screenHeight * 0.1;

    double screenBirdY = gameTop + (gameHeight / 2) + _birdY;

    if (screenBirdY - _birdSize <= gameTop || screenBirdY + _birdSize >= gameTop + gameHeight) {
      return true;
    }

    for (var pipe in _pipes) {
      double pipeX = pipe['x'];
      double topPipeHeight = pipe['topPipeHeight'];
      double bottomPipeHeight = pipe['bottomPipeHeight'];

      if (pipeX <= _birdX + _birdSize && pipeX + _pipeWidth >= _birdX - _birdSize) {
        double topPipeBottom = gameTop + topPipeHeight;
        double bottomPipeTop = gameTop + gameHeight - bottomPipeHeight;

        if (screenBirdY <= topPipeBottom || screenBirdY + _birdSize >= bottomPipeTop) {
          return true;
        }
      }
    }

    return false;
  }

  void _jump() {
    if (!_gameStarted) {
      _startGame();
    }
    if (!_gameOver) {
      setState(() {
        _birdVelocity = _jumpForce;
      });
    }
  }

  void _endGame() {
    _gameOver = true;
    _gameStarted = false;
    _gameTimer?.cancel();
  }

  @override
  void dispose() {
    _gameTimer?.cancel();
    _birdAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final gameHeight = screenHeight * 0.75;
    final gameTop = screenHeight * 0.1;

    return Scaffold(
      body: GestureDetector(
        onTap: _jump,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF87CEEB), Color(0xFF98D8E8), Color(0xFFB0E0E6)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                top: gameTop,
                left: 0,
                right: 0,
                height: gameHeight,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white.withOpacity(0.3), width: 2),
                  ),
                ),
              ),
              Positioned(
                top: gameTop,
                left: 0,
                right: 0,
                height: gameHeight,
                child: ClipRect(
                  child: Stack(
                    children: [
                      AnimatedBuilder(
                        animation: _birdAnimation,
                        builder: (context, child) {
                          double screenBirdY = (gameHeight / 2) + _birdY;
                          return Positioned(
                            left: _birdX - 20,
                            top: screenBirdY - 20 + (_birdAnimation.value * 5),
                            child: Transform.rotate(
                              angle: (_birdVelocity / 15).clamp(-0.4, 0.4),
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white,
                                  border: Border.all(color: Color(0xFF6C63FF), width: 2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.3),
                                      blurRadius: 8,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Icon(Icons.visibility, color: Color(0xFF6C63FF)),
                              ),
                            ),
                          );
                        },
                      ),
                      ..._pipes.map((pipe) {
                        double pipeX = pipe['x'];
                        double topPipeHeight = pipe['topPipeHeight'];
                        double bottomPipeHeight = pipe['bottomPipeHeight'];

                        return Stack(
                          children: [
                            Positioned(
                              left: pipeX,
                              top: 0,
                              child: Container(
                                width: _pipeWidth,
                                height: topPipeHeight,
                                decoration: BoxDecoration(
                                  color: Colors.green.shade700,
                                  borderRadius: BorderRadius.only(
                                    bottomLeft: Radius.circular(8),
                                    bottomRight: Radius.circular(8),
                                  ),
                                  border: Border.all(color: Colors.white, width: 2),
                                ),
                              ),
                            ),
                            Positioned(
                              left: pipeX,
                              bottom: 0,
                              child: Container(
                                width: _pipeWidth,
                                height: bottomPipeHeight,
                                decoration: BoxDecoration(
                                  color: Colors.green.shade700,
                                  borderRadius: BorderRadius.only(
                                    topLeft: Radius.circular(8),
                                    topRight: Radius.circular(8),
                                  ),
                                  border: Border.all(color: Colors.white, width: 2),
                                ),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 40,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.95),
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 10,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Text(
                      'Score: $_score',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF6C63FF),
                      ),
                    ),
                  ),
                ),
              ),
              if (!_gameStarted || _gameOver)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withOpacity(0.8),
                    child: Center(
                      child: GestureDetector(
                        onTap: _jump,
                        child: Container(
                          padding: const EdgeInsets.all(30),
                          margin: const EdgeInsets.symmetric(horizontal: 30),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(25),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 20,
                                offset: Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.visibility, size: 50, color: Color(0xFF6C63FF)),
                              const SizedBox(height: 20),
                              Text(
                                _gameOver ? 'Game Over!' : 'Flappy Eye',
                                style: const TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF6C63FF),
                                ),
                              ),
                              const SizedBox(height: 20),
                              if (_gameOver) ...[
                                Text('Score: $_score', style: const TextStyle(fontSize: 22)),
                                Text('Best: $_bestScore', style: const TextStyle(fontSize: 18)),
                              ] else ...[
                                const Text(
                                  'Tap to fly and avoid the pipes!',
                                  style: TextStyle(fontSize: 16, color: Colors.black54),
                                ),
                              ],
                              const SizedBox(height: 30),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF6C63FF), Color(0xFF8B5FBF)],
                                  ),
                                  borderRadius: BorderRadius.circular(30),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Color(0xFF6C63FF).withOpacity(0.3),
                                      blurRadius: 10,
                                      offset: Offset(0, 5),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  _gameOver ? 'Play Again' : 'Start Game',
                                  style: const TextStyle(fontSize: 18, color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
