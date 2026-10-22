# Gabay Admin (Flutter + Riverpod)

Flutter port of the "Gabay Admin — Dashboard Preview" HTML mockup. UI-only, demo data, no backend.

## Run

```bash
cd gabay_admin
flutter create . --platforms=web,android,ios,windows,macos,linux   # generates platform folders (keeps lib/ and pubspec.yaml)
flutter pub get
flutter run -d chrome
```

## Structure

```
lib/
  main.dart                  App entry (ProviderScope + MaterialApp)
  core/
    theme.dart               Colors, shadows, breakpoints, text helper, ThemeData
    actions.dart             Toast, create dialog launcher, quick-action routing
  data/
    role_config.dart         Per-role nav, stats, activity, quick actions (from the mockup)
  providers/
    app_providers.dart       navProvider (role + page), recordsFilterProvider, spaceLabelsProvider
  widgets/
    common.dart              Card, pill, buttons, page header, grids, form fields, notice
    create_dialog.dart       "Create / Add new" modal
  layout/
    app_shell.dart           Top bar, sidebar (role switcher + nav), page router
  pages/
    overview_page.dart       Stats, activity chart, quick actions, attention panel
    generic_page.dart        Directory table / settings form / audit log
    map_editor_page.dart     2D blueprint, 3D preview, geometry panel, issues list
```

## Behaviour carried over from the mockup

- Role switcher: Superadmin, Mall Supervisor, Mall Admin, Store Owner (resets to Overview).
- Per-role sidebar, stats, recent activity and quick actions.
- Quick-action routing rules (e.g. map editor is Mall Admin only).
- Responsive layout: 4/2 stat columns, stacked panels at <=1050px, icon-only sidebar at <=720px.
- All buttons are preview-only and show a toast; nothing is saved.
