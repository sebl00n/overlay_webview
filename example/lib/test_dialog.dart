import 'package:flutter/material.dart';
import 'package:overlay_webview/overlay_webview.dart';

Future<void> showPropertiesDialog(
    {required BuildContext context, required WebViewController ctrl}) async {
  return showDialog<void>(
    context: context,
    builder: (BuildContext _) {
      return PropertiesDialog(
        ctrl: ctrl,
      );
    },
  );
}

class PropertiesDialog extends StatefulWidget {
  const PropertiesDialog({Key? key, required this.ctrl}) : super(key: key);

  final WebViewController ctrl;

  @override
  _PropertiesDialogState createState() => _PropertiesDialogState();
}

class _PropertiesDialogState extends State<PropertiesDialog> {
  Uri? previewUrl;
  final navigatorKey = GlobalKey<NavigatorState>();
  //final webView = WebViewController(id: "pre");

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
        child: Container(
      //height: 100,
      //width: 100,
      decoration: BoxDecoration(
        border: Border.all(width: 5, color: Colors.red),
      ),
      child: WebView(
        url: "https://google.com",
        controller: this.widget.ctrl,
        onPageNewWindow: (e) {
          print(e.url);
        },
        errorPage: "custom error page<br>"
            "errorCode: {{errorCode}}<br>"
            "errorDescription: {{errorDescription}}<br>"
            "errorURL: {{errorURL}}<br>",
      ),
    ));
  }
}
