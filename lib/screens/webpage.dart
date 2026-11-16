import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// דף מהאתר שמוצג בתוך האפליקציה (תפילון, השכבה)
class WebPageScreen extends StatefulWidget {
  final String title;
  final String url;
  const WebPageScreen({super.key, required this.title, required this.url});

  static void open(BuildContext context, String title, String url) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => WebPageScreen(title: title, url: url)));

  @override
  State<WebPageScreen> createState() => _WebPageScreenState();
}

class _WebPageScreenState extends State<WebPageScreen> {
  late final WebViewController _c;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final home = Uri.parse(widget.url).host;
    _c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
        },
        // קישורים לאתרים אחרים נפתחים בדפדפן
        onNavigationRequest: (r) {
          final u = Uri.tryParse(r.url);
          if (r.isMainFrame && u != null && u.host.isNotEmpty && u.host != home) {
            launchUrl(u, mode: LaunchMode.externalApplication);
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _c.canGoBack()) {
          _c.goBack();
        } else if (context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: Stack(children: [
          WebViewWidget(controller: _c),
          if (_loading) const LinearProgressIndicator(),
        ]),
      ),
    );
  }
}
