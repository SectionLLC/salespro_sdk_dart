## Usage Examples

## Basic Offline-First Setup

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final sdk = SalesProSDK.withApiKey(
    baseUrl: 'https://erp.example.com/api',
    apiKey: 'your-api-key',
    offlineEnabled: true, // default
  );

  // Initialize local storage and auto-sync
  await sdk.init();

  runApp(MyApp(sdk: sdk));
}
```

## Listen to Sync & Connectivity Events

```dart
class MyAppState extends State<MyApp> {
  late final SalesProSDK sdk;

  @override
  void initState() {
    super.initState();

    // Watch connectivity changes
    sdk.events?.onConnectivityChanged((isOnline) {
      if (isOnline) {
        showSnackBar('Back online — syncing changes...');
      } else {
        showSnackBar('You are offline — changes saved locally');
      }
    });

    // Watch sync progress
    sdk.events?.onStatusChanged((status) {
      print('Sync: ${status.state} — ${status.processedItems}/${status.totalItems}');
    });

    // Watch sync errors
    sdk.events?.onError((entityType, entityId, error) {
      print('Sync error on $entityType/$entityId: $error');
    });

    // Watch sync completion
    sdk.events?.onSyncCompleted(() {
      showSnackBar('All changes synced successfully!');
    });
  }
}
```

## Create a Contact While Offline

```dart
Future<void> createContact(SalesProSDK sdk) async {
  // This works whether online or offline:
  // - Online: creates on server, caches locally
  // - Offline: saves locally as dirty, queues for sync
  final contact = await sdk.contacts.create(Contact(
    firstName: 'Jane',
    lastName: 'Doe',
    email: 'jane@example.com',
    type: 'customer',
  ));

  // The contact has a temporary local ID if created offline
  print('Created: ${contact.id} — ${contact.displayName}');

  // When internet returns, the sync manager automatically:
  // 1. Pushes the create to the server
  // 2. Updates the local record with the server-assigned ID
  // 3. Marks the entity as clean
}
```

## Read Data While Offline

```dart
Future<void> loadContacts(SalesProSDK sdk) async {
  // - Online: fetches from server, caches locally, returns results
  // - Offline: returns locally cached contacts with filtering
  final response = await sdk.contacts.list(
    page: 1,
    perPage: 50,
    filters: {'type': 'customer'},
  );

  final contacts = response.items<Contact>(Contact.fromJson);

  // Check if this came from local storage
  if (response.message == 'Loaded from local storage') {
    showOfflineIndicator();
  }
}
```

## Manual Sync Trigger

```dart
Future<void> manualSync(SalesProSDK sdk) async {
  final status = await sdk.syncNow();

  switch (status.state) {
    case SyncState.completed:
      print('Sync completed in ${status.completedAt!.difference(status.startedAt!)}');
      break;
    case SyncState.failed:
      print('Sync failed: ${status.errorMessage}');
      break;
    case SyncState.offline:
      print('No internet — will sync when back online');
      break;
    default:
      break;
  }
}
```

## Check Sync Stats

```dart
Future<void> showSyncStats(SalesProSDK sdk) async {
  final stats = await sdk.getSyncStats();
  final pendingCount = await sdk.getPendingCount();

  for (final stat in stats) {
    print(stat); // e.g. "contact: 150 local, 3 dirty, 0 deleted, 1 queued"
    if (stat.hasUnsyncedChanges) {
      print('  ⚠ ${stat.entityType} has unsynced changes!');
    }
  }

  print('Total pending operations: $pendingCount');
}
```

## Record Payment While Offline

```dart
Future<void> recordPayment(SalesProSDK sdk, String invoiceId) async {
  // Optimistic update: locally updates amount_paid and amount_due
  // Queues the payment for server sync
  final updated = await sdk.invoices.recordPayment(
    invoiceId,
    amount: 250.00,
    paymentMethod: 'credit_card',
  );

  print('Paid: ${updated.amountPaid}, Due: ${updated.amountDue}');
  // When back online, the payment is pushed to the server
}
```

## Adjust Inventory While Offline

```dart
Future<void> adjustStock(SalesProSDK sdk, String productId) async {
  // Optimistic: immediately updates local quantity
  final item = await sdk.inventory.adjust(
    productId: productId,
    quantity: -5, // sold 5 units
    reason: 'sale',
    reference: 'ORD-2024-001',
  );

  print('On hand: ${item.quantityOnHand}');
  // Queued for server sync
}
```

## Full App Example with Offline Banner

```dart
class MyApp extends StatelessWidget {
  final SalesProSDK sdk;
  const MyApp({super.key, required this.sdk});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: StreamBuilder<bool>(
        stream: _connectivityStream(sdk),
        initialData: true,
        builder: (context, snapshot) {
          final isOnline = snapshot.data ?? true;
          return Column(
            children: [
              if (!isOnline)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  color: Colors.orange,
                  child: Text(
                    'OFFLINE — changes will sync when connected',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              Expanded(child: ContactsScreen(sdk: sdk)),
            ],
          );
        },
      ),
    );
  }

  Stream<bool> _connectivityStream(SalesProSDK sdk) {
    final controller = StreamController<bool>();
    sdk.events?.onConnectivityChanged((isOnline) {
      controller.add(isOnline);
    });
    // Emit initial state
    controller.add(sdk.isOnline);
    return controller.stream;
  }
}
```

## How Auto-Sync Works — Flow Diagram

┌─────────────────────────────────────────────────────────────┐
│                     USER ACTION                              │
│  (create, update, delete contact/product/order/etc.)        │
└─────────────┬───────────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────────┐
│              SERVICE (Offline-First)                         │
│                                                              │
│  1. Save to SQLite (is_dirty = 1)      ← Always             │
│  2. Try API call                        ← If online          │
│     ├─ Success → Mark clean locally                           │
│     └─ NetworkException → Enqueue in SyncQueue               │
│  3. If offline → Enqueue in SyncQueue                        │
│  4. Return the local entity                                  │
└─────────────┬───────────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────────┐
│           ConnectivityMonitor                                 │
│                                                              │
│  • Listens to connectivity_plus                              │
│  • Detects: offline → online transition                      │
│  • Emits event to SyncEventBus                               │
└─────────────┬───────────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────────┐
│              SyncManager (Auto-Sync)                          │
│                                                              │
│  Triggered by:                                               │
│  • Connectivity restored (offline → online)                  │
│  • Periodic timer (every 5 min, configurable)                │
│  • Manual sdk.syncNow() call                                 │
│                                                              │
│  Phase 1: Process SyncQueue                                  │
│    → POST/PUT/PATCH/DELETE each pending item                 │
│    → On success: mark completed, mark entity clean           │
│    → On failure: increment attempts, retry later             │
│                                                              │
│  Phase 2: Push Dirty Entities                                │
│    → Find entities with is_dirty = 1 not in queue            │
│    → Enqueue them for update                                 │
│                                                              │
│  Phase 3: Pull Remote Updates                                │
│    → GET /contacts?updated_since=...                         │
│    → GET /products?updated_since=...                         │
│    → Upsert into local SQLite (not dirty)                    │
│                                                              │
│  Phase 4: Cleanup                                            │
│    → Remove completed/permanently-failed queue items         │
└─────────────────────────────────────────────────────────────┘

## Summary of Offline Features

| Feature | Details |
|---|---|
| **Local Storage** | SQLite via `sqflite` — one table per entity + sync queue |
| **Offline-First Writes** | Save locally as dirty → try API → queue on failure |
| **Offline-First Reads** | Try API → cache result → fallback to local on network error |
| **Sync Queue** | Persistent queue with retry limits, status tracking, exponential backoff-ready |
| **Connectivity Monitor** | `connectivity_plus` — detects offline↔online transitions |
| **Auto-Sync on Reconnect** | SyncManager processes queue when internet returns |
| **Periodic Sync** | Configurable interval (default 5 min) |
| **Manual Sync** | `sdk.syncNow()` for pull-to-refresh |
| **Optimistic Updates** | Inventory adjustments & invoice payments update local state immediately |
| **Soft Deletes** | Deleted items stay locally until server confirms the delete |
| **Event System** | `SyncEventBus` with callbacks for status, errors, connectivity, completion |
| **Sync Stats** | Per-entity counts of local/dirty/deleted/queued items |
| **Conflict Tracking** | Dirty flag distinguishes local-only vs. synced data |
| **Configurable** | `offlineEnabled`, `syncInterval`, `syncBatchSize` in `SalesProConfig` |
| **Cleanup** | `clearLocalData()` for logout; `dispose()` for full teardown |