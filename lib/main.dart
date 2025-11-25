import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:tra_x/common/network/trax_api.dart';
import 'package:tra_x/routers/trax_router.dart';

import 'common/global.dart';
import 'common/utils/trax_screen_util.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // set status bar to white
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const MyApp());
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
        scaffoldBackgroundColor: Colors.black,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        splashFactory: NoSplash.splashFactory,
        colorScheme: ColorScheme.light(
          onPrimary: Colors.white, // 主色上的文字颜色
          onSurface: Colors.white, // 表面上的文字颜色
        ),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          centerTitle: true,
          foregroundColor: Colors.black,
        ),
      ),
      // 滑动效果和iOS相同
      scrollBehavior: const CupertinoScrollBehavior(),
      // 默认的动画效果和iOS相同
      defaultTransition: Transition.cupertino,
      // 初始化FlutterSmartDialog
      builder: FlutterSmartDialog.init(
        builder: (context, child) {
          // 初始化屏幕适配
          TraxScreenUtil.init(context);
          // 初始化网络配置
          TraxApi.init(isDebug: true);
          return child!;
        },
      ),
      initialRoute: TraxRouter.welcomePage,
      getPages: TraxRouter.pages,
      routingCallback: TraxRouter.routingCallback,
    );
  }
}
