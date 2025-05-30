import 'package:flutter/material.dart';
import 'package:opencv_eye/hello.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://civodxmuoxjjzxhdqerd.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNpdm9keG11b3hqanp4aGRxZXJkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDg2MDc4NjUsImV4cCI6MjA2NDE4Mzg2NX0.42lCYdcRIxicf0sJczbwUem-b07ICfTKMczi6LI6iks',
  );

  runApp(MyApp());
}
