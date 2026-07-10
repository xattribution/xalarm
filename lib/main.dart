import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones(); // world clock needs the full IANA database
  runApp(const ProviderScope(child: XalarmApp()));
}
