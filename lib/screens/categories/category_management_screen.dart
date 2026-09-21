import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants.dart';
import '../../providers/app_providers.dart';
import '../../data/local/app_database.dart';

/// Mirrors the reference app's "Expenses Category" / "Income Category"
/// screen: emoji + name rows, a pencil to edit, a drag handle to reorder,
/// a minus button to delete, and a "+" in the app bar to add a new one.
class CategoryManagementScreen extends ConsumerWidget {
  final String kind; // 'expense' | 'income'
  const CategoryManagementScreen({super.key, required this.kind});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(categoryRepoProvider);
    final title = kind == 'expense' ? 'Expenses Category' : 'Income Category';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: () => _showEditDialog(context, ref)),
        ],
      ),
      body: StreamBuilder<List<Category>>(
        stream: repo.watchByKind(kind),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final categories = snapshot.data!;
          if (categories.isEmpty) {
            return const Center(child: Text('No categories yet — tap + to add one', style: TextStyle(color: Colors.grey)));
          }

          return ReorderableListView.builder(
            // The default auto-generated drag handle (Flutter adds one on
            // web/desktop automatically) was overlapping our own icon,
            // which made dragging unreliable. Disabling it and wrapping
            // our drag_handle icon in ReorderableDragStartListener below
            // makes that icon the one real, functional handle.
            buildDefaultDragHandles: false,
            itemCount: categories.length,
            onReorder: (oldIndex, newIndex) async {
              final list = [...categories];
              if (newIndex > oldIndex) newIndex -= 1;
              final item = list.removeAt(oldIndex);
              list.insert(newIndex, item);
              await repo.reorder(list.map((c) => c.id).toList());
            },
            itemBuilder: (context, i) {
              final c = categories[i];
              return Container(
                key: ValueKey(c.id),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white12))),
                child: ListTile(
                  leading: IconButton(
                    icon: const Icon(Icons.remove_circle, color: AppColors.expense),
                    onPressed: () => _confirmDelete(context, ref, c),
                  ),
                  title: Text('${c.icon}  ${c.name}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(icon: const Icon(Icons.edit, size: 20), onPressed: () => _showEditDialog(context, ref, existing: c)),
                      const SizedBox(width: 4),
                      ReorderableDragStartListener(
                        index: i,
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(Icons.drag_handle, color: Colors.grey),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, Category c) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete "${c.name}"?'),
        content: const Text('Existing transactions in this category will keep their history but show as Uncategorized.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm == true) {
      await ref.read(categoryRepoProvider).deleteCategory(c.id);
    }
  }

  Future<void> _showEditDialog(BuildContext context, WidgetRef ref, {Category? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final iconCtrl = TextEditingController(text: existing?.icon ?? '📁');

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? 'Add Category' : 'Edit Category'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: iconCtrl,
              decoration: const InputDecoration(labelText: 'Emoji / icon'),
              maxLength: 4,
            ),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              final repo = ref.read(categoryRepoProvider);
              if (existing == null) {
                await repo.addCategory(name: name, icon: iconCtrl.text.trim().isEmpty ? '📁' : iconCtrl.text.trim(), kind: kind);
              } else {
                await repo.renameCategory(existing.id, name);
                await repo.updateIcon(existing.id, iconCtrl.text.trim().isEmpty ? existing.icon : iconCtrl.text.trim());
              }
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
