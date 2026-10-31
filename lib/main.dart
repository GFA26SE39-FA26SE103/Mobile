import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/firebase_push_messaging.dart';
import 'core/providers.dart';

Future<void> main() async {
  // Draw edge to edge; screens sit on the app background instead of a grey system bar.
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final pushMessaging = await createFirebasePushMessaging();
  runApp(
    ProviderScope(
      overrides: [pushMessagingProvider.overrideWithValue(pushMessaging)],
      child: const StaffApp(),
    ),
  );
}
