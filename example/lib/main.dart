import 'package:flutter/material.dart';
import 'package:nativeflow/nativeflow.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NativeFlow.initialize();
  runApp(const MaterialApp(home: Scaffold()));
}
