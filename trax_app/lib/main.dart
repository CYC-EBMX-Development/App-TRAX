import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import 'common/global/global_user_info.dart';
import 'common/services/map_provider.dart';
import 'common/services/gps_interval_settings.dart';
import 'common/utils/app_restart.dart';
import 'common/utils/start_end_marker_icons.dart';
import 'common/utils/start_end_marker_icons_amap.dart';
import 'common/network/trax_api.dart';
import 'common/utils/trax_storage_util.dart';
import 'global.dart';
import 'routers/trax_router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
  );

  // Initialize network
  TraxApi.init(isDebug: Global.testEnv);
  // Initialize storage
  await TraxStorageUtil.init();
  // Restore user info from local storage so owner/guest checks work
  // across app restarts when the user is already logged in.
  _restoreUserInfo();

  // Pre-build shared map marker bitmaps so they render on the first frame.
  await StartEndMarkerIcons.warm();
  await StartEndMarkerIconsAmap.warm();

  // Decide map provider (Google vs AMap) based on cached preference; a
  // background GPS-based refresh is kicked off internally.
  await MapProviderService.init();

  // Load user-selected GPS sampling cadence (Profile → Settings).
  await GpsIntervalSettings.init();

  runApp(const AppWrapper());
}

void _restoreUserInfo() {
  final raw = TraxStorageUtil.getUserInfo();
  if (raw.isEmpty) return;
  try {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    GlobalUserInfo.instance.setUserInfo(
      id: (json['id'] as num?)?.toInt(),
      name: json['username'] as String?,
      email: json['email'] as String?,
      avatar: json['avatarUrl'] as String?,
    );
  } catch (_) {}
}

class AppWrapper extends StatefulWidget {
  const AppWrapper({super.key});

  static _AppWrapperState? _state;

  static Future<void> restart() async {
    await TraxStorageUtil.init();
    _state?.restart();
  }

  @override
  State<AppWrapper> createState() => _AppWrapperState();
}

class _AppWrapperState extends State<AppWrapper> {
  Key _appKey = UniqueKey();

  @override
  void initState() {
    super.initState();
    AppWrapper._state = this;
    AppRestart.register(() async {
      await TraxStorageUtil.init();
      if (mounted) restart();
    });
  }

  void restart() => setState(() => _appKey = UniqueKey());

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(key: _appKey, child: const MyApp());
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      debugShowCheckedModeBanner: false,
      title: Global.appName,
      theme: ThemeData(
        fontFamily: Global.fontFamily,
        scaffoldBackgroundColor: Global.scaffoldBackgroundColor,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        splashFactory: NoSplash.splashFactory,
        colorScheme: ColorScheme.dark(
          onSurface: Colors.black,
          primary: Colors.black,
          surface: Colors.white,
          onPrimary: Colors.white,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          titleTextStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xFF333333)),
          contentTextStyle: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
        ),
        popupMenuTheme: PopupMenuThemeData(
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          centerTitle: true,
          foregroundColor: Colors.black,
          backgroundColor: Colors.transparent,
          systemOverlayStyle: SystemUiOverlayStyle.dark,
          surfaceTintColor: Colors.transparent,
        ),
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: Color(0xFF333333),
          selectionColor: Color(0x33FFB800), // AppColors.primary @ ~20% alpha
          selectionHandleColor: Color(0xFFFFB800),
        ),
      ),
      scrollBehavior: const CupertinoScrollBehavior(),
      defaultTransition: Transition.cupertino,
      builder: FlutterSmartDialog.init(),
      initialRoute: TraxRouter.welcomePage,
      getPages: TraxRouter.pages,
    );
  }
}
