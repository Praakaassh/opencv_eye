import 'package:flutter/material.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class ClickHerePage extends StatelessWidget {
  const ClickHerePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Placeholder();
  }
}
class ModelHandler {
  Interpreter? _interpreter;

  Future<void> loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset('assets/model.tflite');
      print('Model loaded successfully');
    } catch (e) {
      print('Error loading model: $e');
    }
  }

  Interpreter? get interpreter => _interpreter;
}