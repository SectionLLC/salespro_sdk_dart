## Usage Example

```dart
import 'package:flutter/material.dart';
import 'package:salespro_sdk/salespro_sdk.dart';

void main() {
  // 1. Initialize the SDK
  final sdk = SalesProSDK.withApiKey(
    baseUrl: 'https://your-erp.example.com/api',
    apiKey: 'your-api-key-here',
  );

  runApp(MyApp(sdk: sdk));
}

class MyApp extends StatelessWidget {
  final SalesProSDK sdk;
  const MyApp({super.key, required this.sdk});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SalesPro Demo',
      home: ContactsScreen(sdk: sdk),
    );
  }
}

class ContactsScreen extends StatefulWidget {
  final SalesProSDK sdk;
  const ContactsScreen({super.key, required this.sdk});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  List<Contact> _contacts = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await widget.sdk.contacts.list(
        page: 1,
        perPage: 50,
        filters: {'type': 'customer'},
      );
      setState(() {
        _contacts = response.items<Contact>(Contact.fromJson);
        _loading = false;
      });
    } on AuthenticationException catch (e) {
      setState(() {
        _error = 'Auth error: ${e.message}';
        _loading = false;
      });
    } on SalesProException catch (e) {
      setState(() {
        _error = 'Error: ${e.message}';
        _loading = false;
      });
    }
  }

  Future<void> _createContact() async {
    try {
      final newContact = Contact(
        firstName: 'Jane',
        lastName: 'Doe',
        email: 'jane@example.com',
        type: 'customer',
      );

      final created = await widget.sdk.contacts.create(newContact);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Created: ${created.displayName}')),
      );

      _loadContacts();
    } on ValidationException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Validation: ${e.message}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contacts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _createContact,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView.builder(
                  itemCount: _contacts.length,
                  itemBuilder: (context, index) {
                    final contact = _contacts[index];
                    return ListTile(
                      title: Text(contact.displayName),
                      subtitle: Text(contact.email ?? 'No email'),
                      trailing: Text(contact.company ?? ''),
                    );
                  },
                ),
    );
  }
}
```

## Advanced Usage

```dart
// ── Authentication with username/password ──
final sdk = SalesProSDK(
  config: SalesProConfig(
    baseUrl: 'https://erp.example.com/api',
    apiVersion: 'v2',
    timeout: Duration(seconds: 60),
    debug: true,  // logs all requests/responses
  ),
);

await sdk.auth.login(username: 'admin', password: 'secret');
print('Token: ${sdk.accessToken}');

// ── Refreshing tokens ──
if (!sdk.isAuthenticated) {
  await sdk.auth.refresh();
}

// ── Working with orders ──
final order = Order(
  contactId: 'CT-123',
  lineItems: [
    OrderLineItem(
      productId: 'P-456',
      quantity: 3,
      unitPrice: 29.99,
    ),
  ],
  notes: 'Rush delivery',
);
final created = await sdk.orders.create(order);

// ── Convert quote → order ──
final convertedOrder = await sdk.orders.convertFromQuote('QT-789');

// ── Inventory adjustments ──
await sdk.inventory.adjust(
  productId: 'P-456',
  quantity: -5,  // negative = outgoing
  reason: 'sale',
  reference: 'ORD-2024-001',
);

// ── Invoice from order + record payment ──
final invoice = await sdk.invoices.createFromOrder('ORD-2024-001');
await sdk.invoices.recordPayment(
  invoice.id!,
  amount: invoice.totalAmount!,
  paymentMethod: 'credit_card',
);

// ── Reports ──
final sales = await sdk.reports.salesSummary(
  dateFrom: DateTime(2024, 1, 1),
  dateTo: DateTime(2024, 12, 31),
  groupBy: 'month',
);
print('Revenue: \$${sales.totalRevenue}');
print('Margin: ${(sales.margin ?? 0) * 100}%');

// ── Error handling ──
try {
  await sdk.contacts.get('nonexistent-id');
} on NotFoundException {
  print('Contact not found');
} on RateLimitException catch (e) {
  print('Rate limited — retry after ${e.retryAfterSeconds}s');
} on SalesProException catch (e) {
  print('SDK error ${e.statusCode}: ${e.message}');
}
```

## Summary of Key Features

| Feature | Details |
|---|---|
| **Authentication** | API key, username/password, token refresh, auto-bearer injection |
| **Contacts** | Full CRUD, search, filter by type |
| **Products** | Full CRUD, by-SKU lookup, bulk price update, categories |
| **Orders** | Full CRUD, status changes, line-item management, quote conversion, totals calculation |
| **Invoices** | Full CRUD, generate from order, record payments, send via email, PDF download |
| **Quotes** | Full CRUD, send, accept/decline, convert to order |
| **Inventory** | Stock levels, adjustments, warehouse transfers, low-stock alerts, history |
| **Reports** | Sales summary, revenue, inventory valuation, top customers, custom templates, export |
| **Error handling** | Typed exceptions: `AuthenticationException`, `ValidationException`, `NotFoundException`, `RateLimitException`, `ServerException`, `NetworkException` |
| **Pagination** | Built-in `PaginationMeta` parsing from `ApiResponse` |
| **Debug logging** | Toggle via `SalesProConfig.debug` |
| **Flexible field mapping** | `fromJson` accepts both snake_case and camelCase ERP responses |
| **Testable** | Constructor injection for `http.Client`; services accept custom `SalesProHttpClient` |
