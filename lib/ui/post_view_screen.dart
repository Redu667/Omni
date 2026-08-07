import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/feed_item.dart';
import '../models/network.dart';

/// Opens a post inside Omni rather than kicking out to the browser.
///
/// The system back gesture walks the page's own history first, so following
/// links inside a post doesn't drop you straight out of the app.
class PostViewScreen extends StatefulWidget {
  const PostViewScreen({super.key, required this.item});

  final FeedItem item;

  @override
  State<PostViewScreen> createState() => _PostViewScreenState();
}

class _PostViewScreenState extends State<PostViewScreen> {
  late final WebViewController _controller;
  int _progress = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) => setState(() => _progress = p),
        onPageStarted: (_) => setState(() {
          _progress = 0;
          _error = null;
        }),
        onPageFinished: (_) => setState(() => _progress = 100),
        onWebResourceError: (e) {
          // Sub-resources fail constantly on real pages; only surface a
          // failure that took down the main document.
          if (e.isForMainFrame ?? false) {
            setState(() => _error = e.description);
          }
        },
      ))
      ..loadRequest(Uri.parse(widget.item.url!));
  }

  Future<void> _openExternally() async {
    await launchUrl(Uri.parse(widget.item.url!),
        mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _controller.canGoBack()) {
          await _controller.goBack();
        } else {
          navigator.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title?.isNotEmpty == true ? item.title! : item.author,
                style: theme.textTheme.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                Uri.tryParse(item.url ?? '')?.host ?? item.network.label,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Reload',
              onPressed: () => _controller.reload(),
            ),
            IconButton(
              icon: const Icon(Icons.open_in_browser),
              tooltip: 'Open in browser',
              onPressed: _openExternally,
            ),
          ],
          bottom: _progress < 100
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(2),
                  child: LinearProgressIndicator(
                    value: _progress == 0 ? null : _progress / 100,
                    minHeight: 2,
                  ),
                )
              : null,
        ),
        body: _error != null
            ? _LoadFailed(message: _error!, onOpenExternally: _openExternally)
            : WebViewWidget(controller: _controller),
      ),
    );
  }
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.message, required this.onOpenExternally});

  final String message;
  final VoidCallback onOpenExternally;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text("Couldn't load this page",
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              icon: const Icon(Icons.open_in_browser),
              label: const Text('Open in browser instead'),
              onPressed: onOpenExternally,
            ),
          ],
        ),
      ),
    );
  }
}
