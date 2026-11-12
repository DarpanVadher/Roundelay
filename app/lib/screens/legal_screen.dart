import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../legal/legal_data.dart';
import '../widgets/glass.dart';
import '../widgets/roundelay_art.dart';

const _icons = <String, IconData>{
  'privacy-policy': Icons.privacy_tip_outlined,
  'terms-and-conditions': Icons.gavel_outlined,
  'gdpr-compliance': Icons.verified_user_outlined,
  'cookie-consent': Icons.cookie_outlined,
  'legal-basis': Icons.balance_outlined,
  'marketing-consent': Icons.mark_email_unread_outlined,
  'data-deletion': Icons.delete_sweep_outlined,
  'data-retention': Icons.inventory_2_outlined,
  'data-processing-agreements': Icons.handshake_outlined,
  'third-party-disclosure': Icons.travel_explore_outlined,
  'data-security': Icons.lock_outline,
  'data-breach-procedure': Icons.emergency_outlined,
  'intellectual-property': Icons.copyright_outlined,
  'open-source-licences': Icons.code_outlined,
  'payments-and-subscriptions': Icons.credit_card_off_outlined,
};

IconData _iconFor(LegalPage p) => _icons[p.slug] ?? Icons.description_outlined;

class _Badge extends StatelessWidget {
  const _Badge(this.icon, {this.size = 44});
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: s.primaryContainer,
      ),
      child: Icon(icon, size: size * 0.5, color: s.onPrimaryContainer),
    );
  }
}

/// Index of the legal pages. The text ships inside the app, so it reads offline.
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return GlassBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Privacy & legal'),
          backgroundColor: Colors.transparent,
          scrolledUnderElevation: 0,
        ),
        body: SafeArea(
          child: ListView(
            padding: centeredPadding(
              context,
              600,
              const EdgeInsets.fromLTRB(16, 12, 16, 28),
            ),
            children: [
              GlassCard(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    const RoundelayArt(size: 72),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Short, plain, honest', style: text.titleMedium),
                          const SizedBox(height: 4),
                          Text(
                            'No accounts and no servers of ours, so these pages say mostly what we do not do. Summaries, not legal advice.',
                            style: text.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Updated $legalUpdated',
                            style: text.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              for (var i = 0; i < legalPages.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Reveal(
                    delay: Duration(milliseconds: 40 * math.min(i, 6)),
                    child: GlassCard(
                      key: Key('legal-${legalPages[i].slug}'),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => LegalPageScreen(index: i),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          _Badge(_iconFor(legalPages[i])),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${(i + 1).toString().padLeft(2, '0')}  ${legalPages[i].title}',
                                  style: text.titleSmall,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  legalPages[i].summary,
                                  style: text.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            color: scheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class LegalPageScreen extends StatelessWidget {
  const LegalPageScreen({super.key, required this.index});
  final int index;

  LegalPage get page => legalPages[index];

  void _go(BuildContext context, int to) => Navigator.of(context)
      .pushReplacement(
        MaterialPageRoute<void>(builder: (_) => LegalPageScreen(index: to)),
      );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return GlassBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(page.title),
          backgroundColor: Colors.transparent,
          scrolledUnderElevation: 0,
        ),
        body: SafeArea(
          child: SelectionArea(
            child: ListView(
              padding: centeredPadding(
                context,
                680,
                const EdgeInsets.fromLTRB(16, 12, 16, 28),
              ),
              children: [
                // Header: icon, position and the one-line promise.
                GlassCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _Badge(_iconFor(page), size: 52),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              '${(index + 1).toString().padLeft(2, '0')} / ${legalPages.length}',
                              style: text.labelMedium?.copyWith(
                                color: scheme.onSecondaryContainer,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(page.lede, style: text.titleMedium),
                      const SizedBox(height: 8),
                      Text(
                        'Last updated $legalUpdated',
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                for (var i = 0; i < page.sections.length; i++) ...[
                  const SizedBox(height: 14),
                  _SectionCard(number: i + 1, section: page.sections[i]),
                ],
                const SizedBox(height: 18),
                GlassCard(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(Icons.public, color: scheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Full version online', style: text.labelLarge),
                            Text(
                              page.url,
                              style: text.bodySmall?.copyWith(
                                color: scheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        key: const Key('copy-legal-link'),
                        tooltip: 'Copy link',
                        icon: const Icon(Icons.copy),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: page.url));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Link copied')),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: index > 0
                          ? OutlinedButton.icon(
                              key: const Key('legal-prev'),
                              icon: const Icon(Icons.arrow_back),
                              label: Text(
                                legalPages[index - 1].title,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onPressed: () => _go(context, index - 1),
                            )
                          : const SizedBox.shrink(),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: index < legalPages.length - 1
                          ? FilledButton.icon(
                              key: const Key('legal-next'),
                              iconAlignment: IconAlignment.end,
                              icon: const Icon(Icons.arrow_forward),
                              label: Text(
                                legalPages[index + 1].title,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onPressed: () => _go(context, index + 1),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.number, required this.section});
  final int number;
  final LegalSection section;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.primary, width: 1.5),
                ),
                child: Text(
                  '$number',
                  style: text.labelMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  section.title,
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final b in section.blocks) _Block(b),
        ],
      ),
    );
  }
}

/// Renders **bold** and `code` markers produced by tool/build_legal.py.
InlineSpan _inline(String t, TextStyle? base, ColorScheme scheme) {
  final spans = <InlineSpan>[];
  final re = RegExp(r'\*\*(.+?)\*\*|`(.+?)`');
  var at = 0;
  for (final m in re.allMatches(t)) {
    if (m.start > at) spans.add(TextSpan(text: t.substring(at, m.start)));
    if (m.group(1) != null) {
      spans.add(
        TextSpan(
          text: m.group(1),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      );
    } else {
      spans.add(
        TextSpan(
          text: m.group(2),
          style: TextStyle(
            fontFamily: 'monospace',
            backgroundColor: scheme.surfaceContainerHighest,
          ),
        ),
      );
    }
    at = m.end;
  }
  if (at < t.length) spans.add(TextSpan(text: t.substring(at)));
  return TextSpan(style: base, children: spans);
}

class _Block extends StatelessWidget {
  const _Block(this.block);
  final LegalBlock block;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final body = text.bodyMedium?.copyWith(height: 1.5);
    switch (block.kind) {
      case LegalKind.paragraph:
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text.rich(_inline(block.items.first, body, scheme)),
        );
      case LegalKind.bullets:
      case LegalKind.numbered:
        final numbered = block.kind == LegalKind.numbered;
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < block.items.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 3, right: 12),
                        child: numbered
                            ? Container(
                                width: 20,
                                height: 20,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: scheme.primaryContainer,
                                ),
                                child: Text(
                                  '${i + 1}',
                                  style: text.labelSmall?.copyWith(
                                    color: scheme.onPrimaryContainer,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              )
                            : Padding(
                                padding: const EdgeInsets.only(top: 6, left: 5),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: scheme.primary,
                                  ),
                                  child: const SizedBox(width: 8, height: 8),
                                ),
                              ),
                      ),
                      Expanded(
                        child: Text.rich(_inline(block.items[i], body, scheme)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      case LegalKind.table:
        // Phones are narrow: each row becomes a small panel, with the header cells as labels.
        final head = block.rows.first;
        return Column(
          children: [
            for (final row in block.rows.skip(1))
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(_inline(row.first, text.titleSmall, scheme)),
                    for (var c = 1; c < row.length; c++)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '${head[c]}: ',
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              _inline(row[c], body, scheme),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );
    }
  }
}
