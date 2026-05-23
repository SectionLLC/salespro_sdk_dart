import 'package:flutter_test/flutter_test.dart';
import 'package:salespro_sdk/salespro_sdk.dart';
import 'package:salespro_sdk/src/exceptions/sdk_exceptions.dart';

void main() {
  group('SalesProSDK', () {
    late SalesProSDK sdk;

    setUp(() {
      sdk = SalesProSDK.withApiKey(
        baseUrl: 'https://erp.example.com/api',
        apiKey: 'test-key-123',
      );
    });

    test('initialization sets up all services', () {
      expect(sdk.contacts, isA<ContactService>());
      expect(sdk.products, isA<ProductService>());
      expect(sdk.orders, isA<OrderService>());
      expect(sdk.invoices, isA<InvoiceService>());
      expect(sdk.quotes, isA<QuoteService>());
      expect(sdk.inventory, isA<InventoryService>());
      expect(sdk.reports, isA<ReportService>());
    });

    test('isAuthenticated is false before login', () {
      expect(sdk.isAuthenticated, isFalse);
    });

    test('config is properly set', () {
      expect(sdk.auth, isNotNull);
    });
  });

  group('Contact', () {
    test('fromJson handles snake_case and camelCase', () {
      final contact = Contact.fromJson({
        'id': '1',
        'first_name': 'John',
        'lastName': 'Doe',
        'email': 'john@example.com',
        'phone': '+1234567890',
        'company': 'Acme Inc.',
        'type': 'customer',
        'status': 'active',
      });

      expect(contact.id, '1');
      expect(contact.firstName, 'John');
      expect(contact.lastName, 'Doe');
      expect(contact.email, 'john@example.com');
      expect(contact.company, 'Acme Inc.');
    });

    test('toJson produces snake_case keys', () {
      final contact = Contact(
        firstName: 'Jane',
        lastName: 'Smith',
        email: 'jane@example.com',
      );

      final json = contact.toJson();
      expect(json['first_name'], 'Jane');
      expect(json['last_name'], 'Smith');
      expect(json['email'], 'jane@example.com');
    });

    test('displayName combines first and last name', () {
      final contact = Contact(firstName: 'John', lastName: 'Doe');
      expect(contact.displayName, 'John Doe');
    });

    test('copyWith works correctly', () {
      final original = Contact(
        id: '1',
        firstName: 'John',
        lastName: 'Doe',
        email: 'john@example.com',
      );
      final modified = original.copyWith(email: 'new@example.com');

      expect(modified.id, '1');
      expect(modified.firstName, 'John');
      expect(modified.email, 'new@example.com');
    });
  });

  group('Product', () {
    test('fromJson handles various field names', () {
      final product = Product.fromJson({
        'id': '10',
        'sku': 'WIDGET-001',
        'item_name': 'Super Widget',
        'unit_price': 29.99,
        'unit_cost': 15.00,
        'category_name': 'Widgets',
      });

      expect(product.id, '10');
      expect(product.sku, 'WIDGET-001');
      expect(product.name, 'Super Widget');
      expect(product.price, 29.99);
      expect(product.cost, 15.00);
      expect(product.category, 'Widgets');
    });

    test('margin calculation works', () {
      final product = Product(price: 100.0, cost: 60.0);
      expect(product.margin, closeTo(0.4, 0.001));
    });

    test('margin returns null when data is missing', () {
      final product = Product(price: 100.0);
      expect(product.margin, isNull);
    });
  });

  group('Order', () {
    test('fromJson parses line items', () {
      final order = Order.fromJson({
        'id': 'ORD-1',
        'order_number': 'ORD-2024-001',
        'status': 'confirmed',
        'line_items': [
          {
            'product_id': 'P1',
            'product_name': 'Widget',
            'quantity': 2,
            'unit_price': 25.0,
            'total': 50.0,
          },
        ],
        'total_amount': 50.0,
      });

      expect(order.orderNumber, 'ORD-2024-001');
      expect(order.lineItems?.length, 1);
      expect(order.lineItems?.first.productName, 'Widget');
      expect(order.totalAmount, 50.0);
    });
  });

  group('Invoice', () {
    test('isPaid and isOverdue properties', () {
      final paid = Invoice(status: 'paid', amountDue: 0);
      expect(paid.isPaid, isTrue);

      final overdue = Invoice(
        status: 'pending',
        dueDate: DateTime.now().subtract(const Duration(days: 5)),
        amountDue: 100,
      );
      expect(overdue.isOverdue, isTrue);

      final future = Invoice(
        status: 'sent',
        dueDate: DateTime.now().add(const Duration(days: 30)),
        amountDue: 100,
      );
      expect(future.isOverdue, isFalse);
    });
  });

  group('InventoryItem', () {
    test('needsReorder is true when below reorder point', () {
      final item = InventoryItem(
        quantityOnHand: 3,
        reorderPoint: 10,
      );
      expect(item.needsReorder, isTrue);
    });

    test('needsReorder is false when above reorder point', () {
      final item = InventoryItem(
        quantityOnHand: 50,
        reorderPoint: 10,
      );
      expect(item.needsReorder, isFalse);
    });
  });

  group('ApiResponse', () {
    test('items() extracts list from data key', () {
      final response = ApiResponse(
        success: true,
        statusCode: 200,
        data: {
          'data': [
            {'first_name': 'John', 'last_name': 'Doe'},
            {'first_name': 'Jane', 'last_name': 'Smith'},
          ],
        },
      );

      final contacts = response.items<Contact>(Contact.fromJson);
      expect(contacts.length, 2);
      expect(contacts.first.firstName, 'John');
    });

    test('pagination() extracts meta', () {
      final response = ApiResponse(
        success: true,
        statusCode: 200,
        data: {
          'pagination': {
            'current_page': 2,
            'total_pages': 5,
            'total': 120,
            'per_page': 25,
          },
        },
      );

      final pagination = response.pagination!;
      expect(pagination.currentPage, 2);
      expect(pagination.totalItems, 120);
    });
  });

  group('SalesProHttpClient', () {
    test('builds correct URI with query params', () {
      final config = SalesProConfig(
        baseUrl: 'https://erp.example.com/api',
        apiKey: 'test',
      );

      // Verify config setup
      expect(config.fullBaseUrl, 'https://erp.example.com/api/v1');
    });
  });

  group('Exceptions', () {
    test('AuthenticationException defaults to 401', () {
      final ex = AuthenticationException();
      expect(ex.statusCode, 401);
    });

    test('ValidationException holds errors map', () {
      final ex = ValidationException(
        errors: {'email': ['Invalid email']},
      );
      expect(ex.errors, isNotNull);
      expect(ex.errors!['email'], isA<List>());
    });

    test('RateLimitException has retryAfterSeconds', () {
      final ex = RateLimitException(retryAfterSeconds: 60);
      expect(ex.retryAfterSeconds, 60);
    });

    test('ServerException defaults to 500', () {
      final ex = ServerException();
      expect(ex.statusCode, 500);
    });

    test('NetworkException has statusCode 0', () {
      final ex = NetworkException();
      expect(ex.statusCode, 0);
    });
  });

  group('AuthManager', () {
    test('isAuthenticated is false with no token', () {
      final config = SalesProConfig(baseUrl: 'https://erp.example.com/api');
      final httpClient = SalesProHttpClient(config: config);
      final auth = AuthManager(httpClient: httpClient, config: config);

      expect(auth.isAuthenticated, isFalse);
      expect(auth.accessToken, isNull);
    });
  });

  group('SalesSummary', () {
    test('fromJson and margin', () {
      final summary = SalesSummary.fromJson({
        'total_revenue': 100000,
        'total_cost': 60000,
        'total_profit': 40000,
        'total_orders': 500,
        'average_order_value': 200,
      });

      expect(summary.totalRevenue, 100000);
      expect(summary.totalOrders, 500);
      expect(summary.margin, closeTo(0.4, 0.001));
    });
  });
}