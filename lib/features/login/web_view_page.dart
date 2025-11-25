import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tra_x/common/utils/trax_log_util.dart';
import 'package:tra_x/common/widgets/trax_dialog.dart';
import 'package:webview_flutter/webview_flutter.dart';

class WebViewPageBinding implements Bindings {
  @override
  void dependencies() {
    Get.put(WevViewPageController());
  }
}

class WevViewPageController extends GetxController {
  late final String title;
  late final String url;
  late final WebViewController webController;

  @override
  void onInit() {
    title = Get.parameters['title'] ?? '';
    url = Get.parameters['url'] ?? '';
    webController = WebViewController()
      ..addJavaScriptChannel(
        'jsChannel', // TODO: 等后端确定好js函数名称后，再修改此处
        onMessageReceived: (JavaScriptMessage message) {
          TraxLogUtil.debug('jsChannel: ${message.message}');
        },
      )
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            TraxLogUtil.debug('Page started loading: $url');
            TraxDialog.showLoading();
          },
          onPageFinished: (String url) {
            TraxDialog.hideLoading();
          },
        ),
      )
      ..loadRequest(Uri.parse(url));
    super.onInit();
  }
}

class WebViewPage extends GetView<WevViewPageController> {
  const WebViewPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          controller.title,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
      ),
      body: WebViewWidget(controller: controller.webController),
    );
  }
}
