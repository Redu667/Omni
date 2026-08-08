import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

/// Manages the words and accounts hidden from the timeline.
class FiltersScreen extends StatefulWidget {
  const FiltersScreen({super.key});

  @override
  State<FiltersScreen> createState() => _FiltersScreenState();
}

class _FiltersScreenState extends State<FiltersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final _wordField = TextEditingController();
  final _accountField = TextEditingController();

  @override
  void dispose() {
    _tabs.dispose();
    _wordField.dispose();
    _accountField.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Filters'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [Tab(text: 'Words'), Tab(text: 'Accounts')],
        ),
      ),
      body: Column(
        children: [
          if (state.hiddenCount > 0)
            Container(
              width: double.infinity,
              color: theme.colorScheme.surfaceContainerHighest,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                'Hiding ${state.hiddenCount} '
                '${state.hiddenCount == 1 ? 'post' : 'posts'} from the current feed.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _FilterList(
                  controller: _wordField,
                  hintText: 'Word or phrase to hide',
                  helpText:
                      'A single word matches whole words only, so muting '
                      '"art" won\'t hide "start". A phrase matches anywhere. '
                      'Titles and body text are both checked.',
                  emptyText: 'No muted words yet.',
                  values: state.filters.mutedWords,
                  onAdd: state.muteWord,
                  onRemove: state.unmuteWord,
                  icon: Icons.text_fields,
                ),
                _FilterList(
                  controller: _accountField,
                  hintText: 'Account to hide',
                  helpText:
                      'Type it however you like — "@someone", "u/someone" '
                      'and "someone" all match the same account.',
                  emptyText: 'No muted accounts yet.',
                  values: state.filters.mutedAccounts,
                  onAdd: state.muteAccount,
                  onRemove: state.unmuteAccount,
                  icon: Icons.person_off_outlined,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterList extends StatelessWidget {
  const _FilterList({
    required this.controller,
    required this.hintText,
    required this.helpText,
    required this.emptyText,
    required this.values,
    required this.onAdd,
    required this.onRemove,
    required this.icon,
  });

  final TextEditingController controller;
  final String hintText;
  final String helpText;
  final String emptyText;
  final List<String> values;
  final Future<void> Function(String) onAdd;
  final Future<void> Function(String) onRemove;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Future<void> submit() async {
      final value = controller.text;
      if (value.trim().isEmpty) return;
      controller.clear();
      await onAdd(value);
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => submit(),
                  decoration: InputDecoration(
                    hintText: hintText,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                icon: const Icon(Icons.add),
                onPressed: submit,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(helpText,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline)),
          ),
        ),
        Expanded(
          child: values.isEmpty
              ? Center(
                  child: Text(emptyText,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.outline)),
                )
              : ListView(
                  children: [
                    for (final value in values)
                      ListTile(
                        leading: Icon(icon, color: theme.colorScheme.outline),
                        title: Text(value),
                        trailing: IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Remove',
                          onPressed: () => onRemove(value),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
