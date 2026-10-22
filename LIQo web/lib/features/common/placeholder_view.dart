import 'package:flutter/material.dart';

import '../../shared/widgets/common.dart';

/// Stands in for a page that a later phase builds.
class PlaceholderView extends StatelessWidget {
  const PlaceholderView({super.key, required this.eyebrow, required this.title, required this.phase});

  final String eyebrow;
  final String title;
  final String phase;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHead(eyebrow: eyebrow, title: title, subtitle: 'This page is being built.'),
        Notice(bold: 'Coming in $phase.', text: 'The $title page is not available yet.'),
      ],
    );
  }
}

class UnauthorizedView extends StatelessWidget {
  const UnauthorizedView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHead(eyebrow: 'Access', title: 'No access', subtitle: 'This page belongs to a different role.'),
        Notice(bold: 'Not allowed.', text: 'Use the menu on the left to go back to your own pages.'),
      ],
    );
  }
}
