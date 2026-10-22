// Round 7: the typed confirmation only enables once the exact name is typed,
// Cancel answers false, and the page building blocks render as expected.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gabay_admin/core/theme.dart';
import 'package:gabay_admin/shared/widgets/detail_widgets.dart';

Widget _app(Widget home) => MaterialApp(theme: buildTheme(Brightness.light), home: home);

void main() {
  testWidgets('typed confirmation stays disabled until the name matches; Cancel answers false', (tester) async {
    bool? answer;
    await tester.pumpWidget(_app(Scaffold(body: Builder(builder: (ctx) {
      return TextButton(
        onPressed: () async {
          answer = await confirmDangerous(ctx, title: 'Deactivate SM Prime?', impact: 'Hides 12 branches.', name: 'SM Prime', confirmLabel: 'Deactivate mall');
        },
        child: const Text('open'),
      );
    }))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Hides 12 branches.'), findsOneWidget);
    bool enabled() => !tester.widget<IgnorePointer>(find.byKey(dangerConfirmKey)).ignoring;
    expect(enabled(), isFalse);

    await tester.enterText(find.byKey(dangerInputKey), 'SM Prim');
    await tester.pump();
    expect(enabled(), isFalse, reason: 'a near miss does not count');
    await tester.enterText(find.byKey(dangerInputKey), '  SM Prime ');
    await tester.pump();
    expect(enabled(), isTrue, reason: 'spaces around the name are ignored');

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(answer, isFalse);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(dangerInputKey), 'SM Prime');
    await tester.pump();
    await tester.tap(find.text('Deactivate mall'));
    await tester.pumpAndSettle();
    expect(answer, isTrue);
  });

  testWidgets('a detail page shows its cards, hides an empty danger zone, and the Back button is first', (tester) async {
    await tester.pumpWidget(_app(Scaffold(
      body: SingleChildScrollView(
        child: SizedBox(
          width: 1000,
          child: DetailScaffold(
            eyebrow: 'Superadmin / Malls & branches / SM Prime',
            title: 'SM Prime',
            subtitle: 'Mall · 12 branches',
            backPath: '/superadmin/malls',
            backLabel: 'Malls & branches',
            pills: const [Text('Active')],
            children: [
              const DetailCard(title: 'Details', subtitle: 'Name and logo', child: Column(children: [DetailRow('Branches', '12'), DetailRow('Logo URL', null)])),
              DetailCard(title: 'Branches of this mall', child: RecordRow(title: 'SM Mall of Asia', subtitle: 'Pasay', chips: const [Text('Active')], onTap: () {})),
              const DangerZone(actions: []),
            ],
          ),
        ),
      ),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Malls & branches'), findsOneWidget, reason: 'the Back button carries the list name');
    expect(find.text('Details'), findsOneWidget);
    expect(find.text('Branches of this mall'), findsOneWidget);
    expect(find.text('SM Mall of Asia'), findsOneWidget);
    expect(find.text('—'), findsOneWidget, reason: 'an empty value shows a dash');
    expect(find.text('DANGER ZONE'), findsNothing, reason: 'no actions, no zone');
    expect(find.byIcon(Icons.chevron_right), findsOneWidget, reason: 'a tappable row shows a chevron');
  });

  testWidgets('a detail page in its loading state shows skeletons, not a spinner', (tester) async {
    await tester.pumpWidget(_app(const Scaffold(
      body: SingleChildScrollView(
        child: SizedBox(
          width: 1000,
          child: DetailScaffold(eyebrow: 'x', title: 'Loading', subtitle: '', backPath: '/', loading: true, children: []),
        ),
      ),
    )));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('DANGER ZONE'), findsNothing);
  });
}
