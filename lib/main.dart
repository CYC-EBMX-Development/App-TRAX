import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'common/global.dart';
import 'features/login/welcome_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
  ));

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'TraX',
      theme: ThemeData(
        fontFamily: traXFontFamily,
        textTheme: TextTheme(
          displayLarge: const TextStyle(
            fontSize: 50.0,
            fontWeight: FontWeight.bold,
          ),
          titleLarge: const TextStyle(fontSize: 24.0),
          bodyMedium: TextStyle(
            fontSize: 14.0,
            fontFamily: traXFontFamily,
          ),
        ),
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const WelcomePage(),
    );
  }
}