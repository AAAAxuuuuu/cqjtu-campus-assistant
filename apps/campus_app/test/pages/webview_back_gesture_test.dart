import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The service WebView pages tracked `_canGoBack` for their toolbar button but
/// never wired it to the system back gesture, so swiping back from a
/// second-level page (校车预约 → 快速预约, 评教 → 具体表单) popped the whole
/// route and exited the service instead of going back one page.
///
/// A real WebViewController cannot run in the host VM, so this pins the
/// PopScope contract those pages now implement: while inner history exists the
/// route must not pop, and the gesture must be forwarded to `goBack()` instead.
class _WebViewLikePage extends StatefulWidget {
  const _WebViewLikePage({required this.history, this.redirectTrap = false});

  /// Number of inner pages that can be popped before the route may close.
  final int history;

  /// Simulates an SSO redirect loop: `goBack()` "succeeds" but the site
  /// immediately forwards back to the same URL, so `canGoBack` never clears.
  /// This is what 一卡通 does, and it made the page impossible to leave.
  final bool redirectTrap;

  @override
  State<_WebViewLikePage> createState() => _WebViewLikePageState();
}

class _WebViewLikePageState extends State<_WebViewLikePage> {
  late int _depth = widget.history;

  bool get _canGoBack => widget.redirectTrap || _depth > 0;

  int goBackCalls = 0;

  // Mirrors the production budget in campus_service_webview_page.dart.
  static const _maxAttempts = 2;
  int _attempts = 0;
  String? _urlAtLastAttempt;

  String get _currentUrl =>
      widget.redirectTrap ? 'https://ecard/sso' : 'https://site/page$_depth';

  bool get _budgetExhausted => _attempts >= _maxAttempts;

  void _handleBack() {
    final url = _currentUrl;
    if (url == _urlAtLastAttempt) {
      _attempts++;
    } else {
      _attempts = 1;
      _urlAtLastAttempt = url;
    }

    if (_budgetExhausted) {
      // pop(), not maybePop(): maybePop re-consults this PopScope before
      // canPop rebuilds and would recurse forever.
      Navigator.of(context).pop();
      return;
    }

    goBackCalls++;
    setState(() {
      if (_depth > 0) _depth--;
      // A genuine navigation resets the budget.
      if (!widget.redirectTrap) {
        _attempts = 0;
        _urlAtLastAttempt = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_canGoBack || _budgetExhausted,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('校车预约')),
        body: Center(child: Text('inner depth: $_depth')),
      ),
    );
  }
}

void main() {
  Future<void> pumpRoute(
    WidgetTester tester,
    int history, {
    bool redirectTrap = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => _WebViewLikePage(
                    history: history,
                    redirectTrap: redirectTrap,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('back walks inner history instead of leaving the service', (
    tester,
  ) async {
    await pumpRoute(tester, 2);
    expect(find.text('校车预约'), findsOneWidget);

    // First back: consumed by the embedded site.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      find.text('校车预约'),
      findsOneWidget,
      reason: 'route must stay while the site still has history',
    );
    expect(find.text('inner depth: 1'), findsOneWidget);

    // Second back: still inner history left.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('校车预约'), findsOneWidget);
    expect(find.text('inner depth: 0'), findsOneWidget);

    // Third back: history exhausted, now the route may close.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      find.text('校车预约'),
      findsNothing,
      reason: 'with no inner history left the route should pop',
    );
  });

  testWidgets('pops immediately when the page has no inner history', (
    tester,
  ) async {
    await pumpRoute(tester, 0);
    expect(find.text('校车预约'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(
      find.text('校车预约'),
      findsNothing,
      reason: 'a first-level page must not trap the back gesture',
    );
  });

  testWidgets('an SSO redirect loop cannot trap the user', (tester) async {
    // 一卡通: every goBack() lands on a redirect that forwards straight back,
    // so canGoBack stays true forever. Forwarding the gesture unconditionally
    // made the page impossible to leave — this is the bug this test exists for.
    await pumpRoute(tester, 3, redirectTrap: true);
    expect(find.text('校车预约'), findsOneWidget);

    // Press back repeatedly; the budget must run out and release the route.
    for (var i = 0; i < 5; i++) {
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      if (find.text('校车预约').evaluate().isEmpty) break;
    }

    expect(
      find.text('校车预约'),
      findsNothing,
      reason: 'a redirect loop must never make the page inescapable',
    );
  });

  testWidgets('normal browsing does not spend the escape budget', (
    tester,
  ) async {
    // Each back genuinely navigates, so the budget resets every time and all
    // inner history is still walked before the route closes.
    await pumpRoute(tester, 3);

    for (final expected in [
      'inner depth: 2',
      'inner depth: 1',
      'inner depth: 0',
    ]) {
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text(expected), findsOneWidget);
      expect(
        find.text('校车预约'),
        findsOneWidget,
        reason: 'the route must survive while real history remains',
      );
    }
  });
}
