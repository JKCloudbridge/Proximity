import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/recurring_list.dart';
import '../providers/organizer_providers.dart';
import '../widgets/item_picker_sheet.dart';

/// Sprint 11 -- create a new recurring list. No UI spec exists anywhere for
/// this (§4.10's own prose is schema-only) -- a fresh, deliberately simple
/// design: name, cadence, a time-of-day, and an item picker (Order Again's
/// own "Previously Bought" feed, see item_picker_sheet.dart's header for
/// why that feed specifically).
class RecurringListFormScreen extends ConsumerStatefulWidget {
  const RecurringListFormScreen({super.key});

  @override
  ConsumerState<RecurringListFormScreen> createState() => _RecurringListFormScreenState();
}

class _RecurringListFormScreenState extends ConsumerState<RecurringListFormScreen> {
  final _nameController = TextEditingController();
  final _intervalDaysController = TextEditingController(text: '14');
  RecurringListCadence _cadence = RecurringListCadence.weekly;
  TimeOfDay _timeOfDay = const TimeOfDay(hour: 9, minute: 0);
  Map<String, int> _selection = {};
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _intervalDaysController.dispose();
    super.dispose();
  }

  Future<void> _pickItems() async {
    final result = await showItemPickerSheet(context, initialSelection: _selection);
    if (result != null) setState(() => _selection = result);
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Give your list a name')));
      return;
    }
    if (_selection.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add at least one item')));
      return;
    }
    final intervalDays = _cadence == RecurringListCadence.customDays ? int.tryParse(_intervalDaysController.text) : null;
    if (_cadence == RecurringListCadence.customDays && (intervalDays == null || intervalDays <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid number of days')));
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(organizerRepositoryProvider).createList(
            name: name,
            cadence: _cadence.wireValue,
            intervalDays: intervalDays,
            timeOfDay: '${_timeOfDay.hour.toString().padLeft(2, '0')}:${_timeOfDay.minute.toString().padLeft(2, '0')}:00',
            items: [for (final entry in _selection.entries) (variantId: entry.key, quantity: entry.value)],
          );
      ref.invalidate(recurringListsProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New recurring list')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Name', hintText: 'Weekly groceries')),
          const SizedBox(height: 16),
          DropdownButtonFormField<RecurringListCadence>(
            initialValue: _cadence,
            decoration: const InputDecoration(labelText: 'Repeats'),
            items: [for (final c in RecurringListCadence.values) DropdownMenuItem(value: c, child: Text(c.label))],
            onChanged: (value) => setState(() => _cadence = value ?? _cadence),
          ),
          if (_cadence == RecurringListCadence.customDays) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _intervalDaysController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Every how many days'),
            ),
          ],
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Reminder time'),
            subtitle: Text(_timeOfDay.format(context)),
            trailing: const Icon(Icons.schedule),
            onTap: () async {
              final picked = await showTimePicker(context: context, initialTime: _timeOfDay);
              if (picked != null) setState(() => _timeOfDay = picked);
            },
          ),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_selection.isEmpty ? 'Add items' : '${_selection.length} item(s) selected'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickItems,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Save'),
          ),
        ],
      ),
    );
  }
}
