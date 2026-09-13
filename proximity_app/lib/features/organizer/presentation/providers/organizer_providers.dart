import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers.dart';
import '../../data/models/recurring_list.dart';
import '../../data/organizer_repository.dart';

final organizerRepositoryProvider = Provider<OrganizerRepository>((ref) {
  return OrganizerRepository(dio: ref.watch(dioProvider));
});

/// `.autoDispose`: only interesting while the Organizer screen is open,
/// same "re-fetch fresh each visit" convention order_again's own
/// frequentlyBoughtGroupsProvider already established -- a recurring list's
/// `nextRunAt` can change server-side (the cron job, migrations/045) without
/// this app doing anything, so a long-lived cache would just go stale.
final recurringListsProvider = FutureProvider.autoDispose<List<RecurringList>>((ref) {
  return ref.watch(organizerRepositoryProvider).getLists();
});

/// `.family`-keyed on list id, `.autoDispose` -- same shape shop_detail_
/// providers.dart established in Sprint 5 for "a detail screen is pushed/
/// popped per id, nothing should leak between visits to two different ids."
final recurringListDetailProvider = FutureProvider.autoDispose.family<RecurringList, String>((ref, id) {
  return ref.watch(organizerRepositoryProvider).getList(id);
});
