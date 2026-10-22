// Layout sweep: every page of every role, at phone, tablet, laptop and desktop
// widths, with realistic long data from the fake API. Any exception while
// building or laying out a page (RenderFlex overflow included) fails the test
// and names the page and width. Add new pages to role_nav and they are covered.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gabay_admin/core/api_client.dart';
import 'package:gabay_admin/core/router.dart';
import 'package:gabay_admin/core/session.dart';
import 'package:gabay_admin/core/theme.dart';
import 'package:gabay_admin/features/accounts/accounts_service.dart';
import 'package:gabay_admin/features/accounts/assignment_dialog.dart';
import 'package:gabay_admin/features/accounts/create_account_wizard.dart';
import 'package:gabay_admin/features/stores/store_owner_wizard.dart';
import 'package:gabay_admin/features/map_editor/editor_state.dart';
import 'package:gabay_admin/features/map_editor/map_editor_view.dart';
import 'package:gabay_admin/features/map_editor/map_models.dart';
import 'package:gabay_admin/features/map_editor/maps_service.dart';
import 'package:gabay_admin/features/map_editor/ai_scan_dialog.dart';
import 'package:gabay_admin/features/map_editor/blueprint_panel.dart';
import 'package:gabay_admin/features/map_editor/pdf_document.dart';
import 'package:gabay_admin/shared/forms/app_form_dialog.dart';
import 'package:gabay_admin/shared/forms/field_spec.dart';
import 'package:gabay_admin/shared/forms/wizard_dialog.dart';
import 'package:gabay_admin/shared/messaging/messages.dart';
import 'package:gabay_admin/shared/models/paged.dart';
import 'package:gabay_admin/shared/nav/role_nav.dart';


import 'support/fake_api.dart';

/// Phone, small tablet, tablet, the breakpoints themselves and the common laptop and desktop sizes.
const widths = [360.0, 600.0, 768.0, 1024.0, 1050.0, 1051.0, 1200.0, 1366.0, 1440.0, 1920.0];

/// Request groups that may still be loading while the rest of the page is up.
final mixedHangs = {
  'lists-and-reports': RegExp(r'/(accounts|malls|branches|stores|owners|options|announcements|audit|maps)$|/analytics/report'),
  'overview-only': RegExp(r'/analytics/overview'),
  'details-only': RegExp(r'/(malls|branches|accounts|stores|owners|options|announcements)/\d+$'),
  'lookups-only': RegExp(r'/lookups/'),
};

/// Collects every framework error raised while [body] runs, tagged with [label].
Future<void> _collect(List<String> errors, String label, Future<void> Function() body) async {
  final original = FlutterError.onError;
  FlutterError.onError = (details) {
    final first = details.exceptionAsString().split('\n').first;
    // Name the widget and source line that caused it, when the framework knows.
    final m = RegExp(r'error-causing widget was:\s*\n\s*(.+)\n\s*(.+)').firstMatch(details.toString());
    final where = m == null ? '' : '${m.group(1)!.trim()} ${m.group(2)!.trim()}'.replaceAll(RegExp(r'file:///.*/lib/'), 'lib/');
    final msg = '$label: $first  <$where>';
    if (!errors.contains(msg)) {
      errors.add(msg);
      // ignore: avoid_print
      print('OVERFLOW $msg');
      // ignore: avoid_print
      if (m == null) print(details.toString());
    }
  };
  try {
    await body();
  } finally {
    FlutterError.onError = original;
  }
}

Future<ProviderContainer> _signedInApp(WidgetTester tester, String role, {bool hang = false, RegExp? hangWhen}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  ApiClient.instance.dio.httpClientAdapter = FakeApiAdapter(role: role, hang: hang, hangWhen: hangWhen);
  final container = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
  await container.read(sessionProvider.notifier).signIn(
        token: 'test-token',
        user: AuthUser(id: 1, email: longEmail, fullName: 'Maria Consolacion De Los Santos-Villanueva', role: role, isActive: true, mustChangePassword: false),
      );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: Consumer(
        builder: (context, ref, _) => MaterialApp.router(
          theme: buildTheme(Brightness.light),
          routerConfig: ref.watch(routerProvider),
          builder: (context, child) => MessageOverlay(child: child ?? const SizedBox.shrink()),
        ),
      ),
    ),
  );
  return container;
}

/// Lets requests resolve and animations run a bit without waiting on spinners forever.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

/// Every record page a role can open, with the fake API's ids.
List<String> _detailPathsFor(String role) => switch (role) {
      'superadmin' => ['/superadmin/malls/1', '/superadmin/branches/1', '/superadmin/accounts/3', '/superadmin/accounts/4', '/superadmin/accounts/9', '/superadmin/profile-requests/1'],
      'supervisor' => ['/mall-owner/malls/1', '/mall-owner/branches/1', '/mall-owner/admins/3', '/mall-owner/announcements/1', '/mall-owner/stores/1', '/mall-owner/maps?branch=1'],
      'mall_admin' => ['/mall-admin/branch/1', '/mall-admin/stores/1', '/mall-admin/owners/4', '/mall-admin/options/1', '/mall-admin/announcements/1'],
      _ => ['/store-owner/stores/1', '/store-owner/announcements/1'],
    };

void _setWidth(WidgetTester tester, double w) {
  tester.view.physicalSize = Size(w, w < 800 ? 780 : 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Types into a wizard field.
Future<void> _type(WidgetTester tester, String field, String text) async {
  await tester.enterText(find.descendant(of: find.byKey(ValueKey('$field-text')), matching: find.byType(TextField)), text);
  await tester.pump(const Duration(milliseconds: 500));
  await _settle(tester);
}

Future<void> _tapKey(WidgetTester tester, Key key) async {
  await tester.tap(find.byKey(key));
  await _settle(tester);
}

void main() {
  // The create wizards, every step, with long names and every kind of note.
  for (final w in [360.0, 768.0, 1024.0]) {
    testWidgets('create wizards fit at ${w.toInt()} px', (tester) async {
      _setWidth(tester, w);
      final errors = <String>[];
      ApiClient.instance.dio.httpClientAdapter = FakeApiAdapter();
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(body: Builder(builder: (c) {
          ctx = c;
          return const SizedBox.shrink();
        })),
      ));
      const longEmailTaken = 'a.very.long.taken.address.for.layout@example-mall-company.com';

      await _collect(errors, 'account wizard (superadmin) @ ${w.toInt()}', () async {
        runCreateAccountWizard(ctx);
        await _settle(tester);
        await _tapKey(tester, CreateAccountWizard.roleKey('superadmin'));
        await _tapKey(tester, CreateAccountWizard.nextKey);
        await _type(tester, 'fullName', 'Maria Consolacion De Los Santos-Villanueva');
        await _type(tester, 'email', longEmailTaken);
        await _type(tester, 'email', 'a.very.long.pending.address.for.layout@example-mall-company.com');
        await _tapKey(tester, CreateAccountWizard.nextKey);
        await _tapKey(tester, CreateAccountWizard.nextKey);
        await tester.tap(find.text('Yes, create superadmin'));
        await _settle(tester);
        await _tapKey(tester, CreateAccountWizard.nextKey);
      });

      await _collect(errors, 'account wizard (mall admin) @ ${w.toInt()}', () async {
        runCreateAccountWizard(ctx, fixedRole: 'mall_admin', mall: const LookupItem(id: 1, label: 'SM Prime Holdings Incorporated'));
        await _settle(tester);
        await _type(tester, 'fullName', 'Maria Consolacion De Los Santos-Villanueva');
        await _type(tester, 'email', 'maria.free@example-mall-company.com');
        await _tapKey(tester, CreateAccountWizard.nextKey);
        await tester.tap(find.byKey(AssignmentDialog.branchKey));
        await _settle(tester);
        await tester.tap(find.text('$longName · $longName').last);
        await _settle(tester);
        await _tapKey(tester, CreateAccountWizard.nextKey);
        await tester.tap(find.byKey(WizardFrame.closeKey));
        await _settle(tester);
        await tester.tap(find.text('Discard'));
        await _settle(tester);
      });

      await _collect(errors, 'store owner wizard @ ${w.toInt()}', () async {
        runStoreOwnerWizard(ctx);
        await _settle(tester);
        await tester.tap(find.text('Choose a store…'));
        await _settle(tester);
        await tester.tap(find.text('$longName · $longName').last);
        await _settle(tester);
        await _tapKey(tester, StoreOwnerWizard.nextKey);
        await _type(tester, 'fullName', 'Maria Consolacion De Los Santos-Villanueva');
        await _type(tester, 'email', 'a.very.long.sleepy.address.for.layout@example-mall-company.com');
        await _type(tester, 'email', 'a.very.long.owner.address.for.layout@example-mall-company.com');
        await _tapKey(tester, StoreOwnerWizard.nextKey);
        await _tapKey(tester, StoreOwnerWizard.nextKey);
        await _tapKey(tester, StoreOwnerWizard.nextKey);
      });
      tester.takeException();
      expect(errors, isEmpty, reason: 'Layout problems:\n${errors.join('\n')}');
    });
  }

  for (final role in roleNavs.keys) {
    for (final w in widths) {
      testWidgets('$role pages fit at ${w.toInt()} px', (tester) async {
        _setWidth(tester, w);
        final errors = <String>[];
        final container = await _signedInApp(tester, role);
        addTearDown(container.dispose);
        final router = container.read(routerProvider);
        final nav = navForRole(role);

        final paths = [for (final item in nav.items) item.path, ..._detailPathsFor(role)];
        for (final path in paths) {
          await _collect(errors, '$path @ ${w.toInt()}', () async {
            router.go(path);
            await _settle(tester);
            // Lists: open the first row's page (it navigates), then come back.
            final chevron = find.byIcon(Icons.chevron_right);
            if (chevron.evaluate().isNotEmpty) {
              await tester.tap(chevron.first, warnIfMissed: false);
              await _settle(tester);
            }
          });
        }
        await _collect(errors, '/unauthorized @ ${w.toInt()}', () async {
          router.go('/unauthorized');
          await _settle(tester);
        });
        // Clear anything the framework also recorded, so the report below is the one that counts.
        tester.takeException();
        expect(errors, isEmpty, reason: 'Layout problems:\n${errors.join('\n')}');
      });
    }
  }

  // Half-loaded states: some requests never answer while the rest of the page is up.
  for (final role in roleNavs.keys) {
    for (final entry in mixedHangs.entries) {
      for (final w in [360.0, 1366.0]) {
        testWidgets('$role pages fit while ${entry.key} are loading at ${w.toInt()} px', (tester) async {
          _setWidth(tester, w);
          final errors = <String>[];
          final container = await _signedInApp(tester, role, hangWhen: entry.value);
          addTearDown(container.dispose);
          final router = container.read(routerProvider);
          final nav = navForRole(role);
          final paths = [for (final item in nav.items) item.path, ..._detailPathsFor(role)];
          for (final path in paths) {
            await _collect(errors, '$path (${entry.key} loading) @ ${w.toInt()}', () async {
              router.go(path);
              await _settle(tester);
            });
          }
          tester.takeException();
          expect(errors, isEmpty, reason: 'Layout problems while ${entry.key} are loading:\n${errors.join('\n')}');
        });
      }
    }
  }

  // Loading states: the server never answers, every page shows its skeletons.
  for (final role in roleNavs.keys) {
    for (final w in widths) {
      testWidgets('$role pages fit while loading at ${w.toInt()} px', (tester) async {
        _setWidth(tester, w);
        final errors = <String>[];
        final container = await _signedInApp(tester, role, hang: true);
        addTearDown(container.dispose);
        final router = container.read(routerProvider);
        final nav = navForRole(role);
        final paths = [for (final item in nav.items) item.path, ..._detailPathsFor(role)];
        for (final path in paths) {
          await _collect(errors, '$path (loading) @ ${w.toInt()}', () async {
            router.go(path);
            await _settle(tester);
          });
        }
        tester.takeException();
        expect(errors, isEmpty, reason: 'Layout problems while loading:\n${errors.join('\n')}');
      });
    }
  }

  for (final w in widths) {
    testWidgets('signed-out pages fit at ${w.toInt()} px', (tester) async {
      _setWidth(tester, w);
      final errors = <String>[];
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      ApiClient.instance.dio.httpClientAdapter = FakeApiAdapter();
      final container = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
      addTearDown(container.dispose);
      await _collect(errors, '/login @ ${w.toInt()}', () async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: Consumer(
              builder: (context, ref, _) => MaterialApp.router(
                theme: buildTheme(Brightness.light),
                routerConfig: ref.watch(routerProvider),
                builder: (context, child) => MessageOverlay(child: child ?? const SizedBox.shrink()),
              ),
            ),
          ),
        );
        await _settle(tester);
      });
      await _collect(errors, '/change-password @ ${w.toInt()}', () async {
        await container.read(sessionProvider.notifier).signIn(
              token: 'test-token',
              user: const AuthUser(id: 1, email: longEmail, fullName: 'Maria Consolacion De Los Santos-Villanueva', role: 'supervisor', isActive: true, mustChangePassword: true),
            );
        await _settle(tester);
      });
      tester.takeException();
      expect(errors, isEmpty, reason: 'Layout problems:\n${errors.join('\n')}');
    });
  }

  // The editor is gated below 900 px; above that it must fit with a document open.
  for (final w in [900.0, 1024.0, 1440.0]) {
    testWidgets('map editor with a document fits at ${w.toInt()} px', (tester) async {
      _setWidth(tester, w);
      final errors = <String>[];
      // The full editor (Round 18: the easy editor is the default and has its own sweep below).
      SharedPreferences.setMockInitialValues({'map.editor.guided': false});
      final prefs = await SharedPreferences.getInstance();
      ApiClient.instance.dio.httpClientAdapter = FakeApiAdapter(role: 'mall_admin');
      final container = ProviderContainer(overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        mapListProvider.overrideWith((ref) async => const [
              MapStatus(branchId: 7, branchName: longName, mallName: 'SM Prime Holdings Incorporated', hasMap: true, draftVersion: 3, publishedVersion: 2, spaceCount: 12),
            ]),
      ]);
      addTearDown(container.dispose);
      final doc = LayoutDoc(buildings: [
        Building(id: 'bd-1', name: 'Main building with a long descriptive name', levels: [
          Level(id: 'lv-1', name: 'Ground floor'),
          Level(id: 'lv-2', name: 'Second floor with a long name'),
        ]),
      ]);
      container.read(editorProvider.notifier).loadLocal(doc, editable: true);
      await _collect(errors, 'map editor @ ${w.toInt()}', () async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: buildTheme(Brightness.light),
              // Same order as the real app: the message overlay sits above the Scaffold.
              home: MessageOverlay(child: Scaffold(body: SingleChildScrollView(child: SizedBox(width: w - 300, child: const MapEditorView())))),
            ),
          ),
        );
        await _settle(tester);
        // Every right-panel tab.
        for (final tab in ['Issues', 'Structure', 'Blueprint', 'Properties']) {
          final f = find.text(tab);
          if (f.evaluate().isNotEmpty) {
            await tester.tap(f.first);
            await _settle(tester);
          }
        }
      });
      tester.takeException();
      expect(errors, isEmpty, reason: 'Layout problems:\n${errors.join('\n')}');
    });
  }

  // Round 17: with the 3D preview open and collapsed beside the canvas.
  for (final (w, open3d) in [
    for (final w in [900.0, 1024.0, 1440.0, 1920.0])
      for (final o in [true, false]) (w, o),
  ]) {
    testWidgets('map editor with a plan and an AI proposal fits at ${w.toInt()} px (3D ${open3d ? 'open' : 'collapsed'})', (tester) async {
      _setWidth(tester, w);
      final errors = <String>[];
      SharedPreferences.setMockInitialValues({'map3d.collapsed': !open3d, 'map.editor.guided': false});
      final prefs = await SharedPreferences.getInstance();
      ApiClient.instance.dio.httpClientAdapter = FakeApiAdapter(role: 'mall_admin');
      final container = ProviderContainer(overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        mapListProvider.overrideWith((ref) async => const [
              MapStatus(branchId: 7, branchName: longName, mallName: 'SM Prime Holdings Incorporated', hasMap: true, draftVersion: 3, publishedVersion: 2, spaceCount: 12),
            ]),
      ]);
      addTearDown(container.dispose);
      final doc = LayoutDoc(buildings: [
        Building(id: 'bd-1', name: 'Main building with a long descriptive name', levels: [
          Level(id: 'lv-1', name: 'Ground floor', backdrop: Backdrop(id: 'abcdef0123456789abcdef0123456789', cx: 25, cz: 15, mpp: 0.05)),
        ]),
      ]);
      final n = container.read(editorProvider.notifier);
      n.loadLocal(doc, editable: true);
      n.setCropBox([0.1, 0.1, 0.7, 0.8]);
      n.debugSetProposal(Proposal.fromJson(FakeApiAdapter.aiProposal()));
      await _collect(errors, 'map editor with AI proposal @ ${w.toInt()}', () async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: buildTheme(Brightness.light),
              home: MessageOverlay(child: Scaffold(body: SingleChildScrollView(child: SizedBox(width: w - 300, child: const MapEditorView())))),
            ),
          ),
        );
        await _settle(tester);
        final f = find.text('Blueprint');
        if (f.evaluate().isNotEmpty) {
          await tester.tap(f.first);
          await _settle(tester);
        }
      });
      tester.takeException();
      expect(errors, isEmpty, reason: 'Layout problems:\n${errors.join('\n')}');
    });
  }

  // The easy editor (Round 18): every step, with a room, a wall and the door
  // sizes showing, an AI proposal waiting and long names.
  for (final w in [900.0, 1024.0, 1440.0, 1920.0]) {
    testWidgets('easy map editor fits at ${w.toInt()} px, every step', (tester) async {
      _setWidth(tester, w);
      final errors = <String>[];
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      ApiClient.instance.dio.httpClientAdapter = FakeApiAdapter(role: 'mall_admin');
      final container = ProviderContainer(overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        mapListProvider.overrideWith((ref) async => const [
              MapStatus(branchId: 7, branchName: longName, mallName: 'SM Prime Holdings Incorporated', hasMap: true, draftVersion: 3, publishedVersion: 2, spaceCount: 12),
            ]),
      ]);
      addTearDown(container.dispose);
      final doc = LayoutDoc(buildings: [
        Building(id: 'bd-1', name: 'Main building with a long descriptive name', levels: [
          Level(
            id: 'lv-1',
            name: 'Ground floor',
            backdrop: Backdrop(id: 'abcdef0123456789abcdef0123456789', cx: 25, cz: 15, mpp: 0.05),
            outline: Poly(outer: [[0, 0], [50, 0], [50, 30], [0, 30]]),
            walls: [Wall(id: 'w-1', a: [0, 15], b: [50, 15], t: 0.15, kind: 'solid')],
            spaces: [
              Space(id: 'sp-1', name: longName, type: 'retail', shape: Poly(outer: [[0, 0], [25, 0], [25, 15], [0, 15]])),
              Space(id: 'sp-2', name: '', type: 'food', shape: Poly(outer: [[25, 0], [50, 0], [50, 15], [25, 15]])),
            ],
          ),
        ]),
      ]);
      final n = container.read(editorProvider.notifier);
      n.loadLocal(doc, editable: true, guided: true);
      n.debugSetProposal(Proposal.fromJson(FakeApiAdapter.aiProposal()));
      await _collect(errors, 'easy map editor @ ${w.toInt()}', () async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: buildTheme(Brightness.light),
              home: MessageOverlay(child: Scaffold(body: SingleChildScrollView(child: SizedBox(width: w - 300, child: const MapEditorView())))),
            ),
          ),
        );
        await _settle(tester);
        for (var step = 0; step < 5; step++) {
          n.setGuidedStep(step);
          await _settle(tester);
          if (step == 1) {
            n.startCalibration();
            await _settle(tester);
            n.cancelCalibration();
          }
          if (step == 3) {
            n.select(const Selection(SelKind.space, 'sp-1'));
            await _settle(tester);
            n.select(const Selection(SelKind.wall, 'w-1'));
            n.setGuidedTool(GuidedTool.addDoor);
            await _settle(tester);
          }
        }
      });
      tester.takeException();
      expect(errors, isEmpty, reason: 'Layout problems:\n${errors.join('\n')}');
    });
  }

  for (final w in [360.0, 1024.0]) {
    testWidgets('dialogs fit at ${w.toInt()} px', (tester) async {
      _setWidth(tester, w);
      final errors = <String>[];
      ApiClient.instance.dio.httpClientAdapter = FakeApiAdapter();
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(body: Builder(builder: (c) {
          ctx = c;
          return const SizedBox.shrink();
        })),
      ));

      await _collect(errors, 'assignment dialog (mall admin) @ ${w.toInt()}', () async {
        showDialog<void>(
          context: ctx,
          builder: (_) => AssignmentDialog(
            role: 'mall_admin',
            title: 'Assignments for Maria Consolacion De Los Santos-Villanueva',
            subtitle: 'Saving replaces the whole set. The mall admin can manage only the branches listed here.',
            submitLabel: 'Save',
            initial: const AccountAssignments(branches: [
              AssignedBranch(id: 1, name: longName, mallId: 1, mallName: 'SM Prime Holdings Incorporated'),
              AssignedBranch(id: 2, name: 'Galleria', mallId: 2, mallName: 'Robinsons Land Corporation Malls Division'),
            ]),
            onSubmit: (_) async {},
          ),
        );
        await _settle(tester);
        Navigator.of(ctx, rootNavigator: true).pop();
        await _settle(tester);
      });

      await _collect(errors, 'assignment dialog (supervisor) @ ${w.toInt()}', () async {
        showDialog<void>(
          context: ctx,
          builder: (_) => AssignmentDialog(
            role: 'supervisor',
            title: 'Create account',
            subtitle: 'Step 2 of 2. Which malls or branches can this person oversee?',
            submitLabel: 'Create',
            initial: const AccountAssignments(
              malls: [LookupItem(id: 1, label: 'SM Prime Holdings Incorporated Shopping Centers Division')],
              branches: [AssignedBranch(id: 1, name: '$longName · $longName')],
            ),
            onSubmit: (_) async {},
          ),
        );
        await _settle(tester);
        Navigator.of(ctx, rootNavigator: true).pop();
        await _settle(tester);
      });

      await _collect(errors, 'branch form @ ${w.toInt()}', () async {
        showAppForm(
          context: ctx,
          title: 'Add the first branch of SM Prime Holdings Incorporated Shopping Centers Division?',
          subtitle: 'A mall needs at least one branch before a mall admin can be assigned to it. You can also do this later from the mall row menu.',
          submitLabel: 'Create branch',
          cancelLabel: 'Later',
          initial: {
            'mall': const [LookupItem(id: 1, label: 'SM Prime Holdings Incorporated Shopping Centers Division')],
          },
          fields: const [
            FieldSpec(name: 'mall', label: 'Mall', kind: FieldKind.lookup, lookup: 'malls', required: true, readOnly: true),
            FieldSpec(name: 'name', label: 'Branch name', required: true, maxLength: 200, hint: 'e.g. SM Mall of Asia'),
            FieldSpec(name: 'branches', label: 'Branches', kind: FieldKind.multiLookup, lookup: 'branches', hint: 'Add branches…'),
            FieldSpec(name: 'address', label: 'Address', kind: FieldKind.multiline, maxLength: 500, help: 'A long help line that explains what to type here and why it matters for shoppers.'),
          ],
          onSubmit: (_) async {},
        );
        await _settle(tester);
        Navigator.of(ctx, rootNavigator: true).pop();
        await _settle(tester);
      });

      await _collect(errors, 'confirm dialog @ ${w.toInt()}', () async {
        confirmDialog(
          ctx,
          title: 'Deactivate SM Prime Holdings Incorporated Shopping Centers Division?',
          message: 'This hides 12 branches and 340 stores from supervisors, mall admins and store owners. Access is paused for 9 mall admins until it is reactivated. Nothing is deleted.',
          confirmLabel: 'Deactivate',
        );
        await _settle(tester);
        Navigator.of(ctx, rootNavigator: true).pop();
        await _settle(tester);
      });

      await _collect(errors, 'AI scan @ ${w.toInt()}', () async {
        final done = Completer<String?>();
        showAiScan(ctx, done: done.future, branchId: 1, backdropKey: 'k', crop: const [0.2, 0.2, 0.8, 0.9], loadImage: () async => null);
        await _settle(tester);
        done.complete(null);
        await _settle(tester);
      });

      await _collect(errors, 'AI scan, reading failed @ ${w.toInt()}', () async {
        final done = Completer<String?>();
        showAiScan(ctx, done: done.future, branchId: 1, backdropKey: 'k', loadImage: () async => null);
        await _settle(tester);
        done.complete('The chosen AI model could not take this reading, so nothing was added and no credits were used. Try again in a moment; if it keeps happening, a superadmin can choose another model in Settings.');
        await _settle(tester);
        await tester.tap(find.text('Close'));
        await _settle(tester);
      });

      await _collect(errors, 'drawing unit picker @ ${w.toInt()}', () async {
        showDialog<String>(context: ctx, builder: (_) => const DrawingUnitPicker(fileName: 'SM Prime Holdings Incorporated — Ground floor architectural plan, revision 14 (final).dxf'));
        await _settle(tester);
        await tester.tap(find.text('Place at this scale'));
        await _settle(tester);
        Navigator.of(ctx, rootNavigator: true).pop();
        await _settle(tester);
      });

      await _collect(errors, 'PDF page picker @ ${w.toInt()}', () async {
        showDialog<int>(context: ctx, builder: (_) => PdfPagePicker(doc: _SweepPdf()));
        await _settle(tester);
        await tester.ensureVisible(find.byKey(const ValueKey('pdf-page-24')));
        await _settle(tester);
        await tester.tap(find.byKey(const ValueKey('pdf-page-24')));
        await _settle(tester);
        Navigator.of(ctx, rootNavigator: true).pop();
        await _settle(tester);
      });

      await _collect(errors, 'one-time secret @ ${w.toInt()}', () async {
        showOneTimeSecret(ctx, title: 'Account created', message: 'Temporary password for $longEmail:', secret: 'Xk9#mPq2vL8wR4tZ');
        await _settle(tester);
        Navigator.of(ctx, rootNavigator: true).pop();
        await _settle(tester);
      });

      tester.takeException();
      expect(errors, isEmpty, reason: 'Layout problems:\n${errors.join('\n')}');
    });
  }
}

/// A long PDF for the page picker: many pages, and previews that never arrive (loading state).
class _SweepPdf implements PdfDocument {
  @override
  int get pageCount => 36;

  @override
  Future<Uint8List> render(int page, {required int maxSide}) => Completer<Uint8List>().future;

  @override
  void dispose() {}
}
