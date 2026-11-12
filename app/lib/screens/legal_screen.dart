import 'package:flutter/material.dart';

import '../legal/legal_data.dart';
import '../widgets/glass.dart';
import '../widgets/roundelay_art.dart';

/// Index of the legal pages. The text ships inside the app, so it reads offline.
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return GlassBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Privacy & legal'),
          backgroundColor: Colors.transparent,
          scrolledUnderElevation: 0,
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Roundelay has no accounts and no servers of ours, so these pages are short. Plain-language summaries, not legal advice. Updated $legalUpdated.',
                    style: text.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  for (var i = 0; i < legalPages.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Reveal(
                        delay: Duration(milliseconds: 40 * (i < 6 ? i : 6)),
                        child: GlassCard(
                          key: Key('legal-${legalPages[i].slug}'),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => LegalPageScreen(
                                page: legalPages[i],
                                number: i + 1,
                              ),
                            ),
                          ),
                          child: ListTile(
                            leading: Text(
                              (i + 1).toString().padLeft(2, '0'),
                              style: text.titleMedium?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            title: Text(legalPages[i].title),
                            subtitle: Text(legalPages[i].summary),
                            trailing: const Icon(Icons.chevron_right),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LegalPageScreen extends StatelessWidget {
  const LegalPageScreen({super.key, required this.page, required this.number});
  final LegalPage page;
  final int number;

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
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: SelectionArea(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'LEGAL · ${number.toString().padLeft(2, '0')} OF ${legalPages.length}',
                      style: text.labelSmall?.copyWith(
                        color: scheme.primary,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(page.lede, style: text.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Last updated $legalUpdated',
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    for (final s in page.sections) ...[
                      const SizedBox(height: 24),
                      Text(s.title, style: text.titleLarge),
                      const SizedBox(height: 8),
                      for (final b in s.blocks) _Block(b),
                    ],
                    const SizedBox(height: 28),
                    Text('Full version online', style: text.labelLarge),
                    Text(
                      page.url,
                      style: text.bodySmall?.copyWith(color: scheme.primary),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
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
    final body = text.bodyMedium;
    switch (block.kind) {
      case LegalKind.paragraph:
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text.rich(_inline(block.items.first, body, scheme)),
        );
      case LegalKind.bullets:
      case LegalKind.numbered:
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < block.items.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 24,
                        child: Text(
                          block.kind == LegalKind.bullets ? '•' : '${i + 1}.',
                          style: body,
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
        // Phones are narrow: each row becomes a small card, with the header cells as labels.
        final head = block.rows.first;
        return Column(
          children: [
            for (final row in block.rows.skip(1))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GlassCard(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var c = 0; c < row.length; c++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
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
              ),
          ],
        );
    }
  }
}
