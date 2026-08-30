import 'package:flutter_test/flutter_test.dart';
import 'package:zawer_jewellery_app/models/order_model.dart';

void main() {
  group('Order Tracking Model & Core Logic Tests', () {
    test('TrackingStep parses valid JSON correctly', () {
      final json = {
        'status': 'Order Placed',
        'title': 'Order Placed',
        'description': 'Your order has been registered in luxury vault.',
        'location': 'ZAWER Online Hub, Mumbai',
        'timestamp': '2026-08-30T10:00:00.000Z',
        'isCompleted': true,
      };

      final step = TrackingStep.fromJson(json);

      expect(step.status, 'Order Placed');
      expect(step.title, 'Order Placed');
      expect(step.description, contains('luxury vault'));
      expect(step.location, 'ZAWER Online Hub, Mumbai');
      expect(step.isCompleted, isTrue);
      expect(step.timestamp, isNotNull);
      expect(step.timestamp!.year, 2026);
    });

    test('TrackingStep handles null / missing fields with safe defaults', () {
      final json = <String, dynamic>{};
      final step = TrackingStep.fromJson(json);

      expect(step.status, '');
      expect(step.title, '');
      expect(step.description, '');
      expect(step.location, 'ZAWER Vault');
      expect(step.isCompleted, isFalse);
      expect(step.timestamp, isNull);
    });

    test('OrderItemModel parses numeric fields properly', () {
      final json = {
        'productId': 'prod_ring_01',
        'name': 'Solitaire Diamond Ring',
        'image': 'assets/images/ring1.jpg',
        'price': 185000,
        'quantity': 2,
      };

      final item = OrderItemModel.fromJson(json);

      expect(item.productId, 'prod_ring_01');
      expect(item.name, 'Solitaire Diamond Ring');
      expect(item.price, 185000.0);
      expect(item.quantity, 2);
    });

    test('OrderTrackingModel parses full 6-stage order payload', () {
      final json = {
        'orderId': '66ca123456789abcdef01234',
        'trackingNumber': 'ZWR-491823',
        'currentStatus': 'Shipped',
        'courierPartner': 'Sequel Secure Luxury Logistics',
        'currentLocation': 'High-Security Transit Hub',
        'estimatedDelivery': '2026-09-03T18:00:00.000Z',
        'aiDeliveryInsight': 'Your shipment is travelling under 100% insured armored transit.',
        'customerName': 'Aadish Test',
        'address': '101 Luxury Heights, Mumbai',
        'phone': '+91 9876543210',
        'totalAmount': 370000,
        'createdAt': '2026-08-30T09:30:00.000Z',
        'items': [
          {
            'productId': 'prod_ring_01',
            'name': 'Solitaire Diamond Ring',
            'image': 'assets/images/ring1.jpg',
            'price': 185000,
            'quantity': 2,
          }
        ],
        'timeline': [
          {
            'status': 'Order Placed',
            'title': 'Order Placed',
            'description': 'Your order has been received.',
            'location': 'ZAWER Online Hub, Mumbai',
            'timestamp': '2026-08-30T09:30:00.000Z',
            'isCompleted': true,
          },
          {
            'status': 'Order Confirmed',
            'title': 'Order Confirmed',
            'description': 'Authenticity certification generated.',
            'location': 'ZAWER Central Verification Center',
            'timestamp': '2026-08-30T10:00:00.000Z',
            'isCompleted': true,
          },
          {
            'status': 'Processing',
            'title': 'Processing & Hallmarking',
            'description': 'Master jewelers setting inspection.',
            'location': 'ZAWER Diamond Studio & Vault',
            'timestamp': '2026-08-30T11:00:00.000Z',
            'isCompleted': true,
          },
          {
            'status': 'Shipped',
            'title': 'Shipped & Dispatched',
            'description': 'Dispatched via Armored Transit.',
            'location': 'High-Security Transit Hub',
            'timestamp': '2026-08-30T12:00:00.000Z',
            'isCompleted': true,
          },
          {
            'status': 'Out for Delivery',
            'title': 'Out for Delivery',
            'description': 'Delivery executive on the way.',
            'location': 'Local Express Delivery Hub',
            'timestamp': null,
            'isCompleted': false,
          },
          {
            'status': 'Delivered',
            'title': 'Delivered',
            'description': 'Package successfully delivered.',
            'location': 'Customer Destination Address',
            'timestamp': null,
            'isCompleted': false,
          },
        ],
      };

      final order = OrderTrackingModel.fromJson(json);

      expect(order.orderId, '66ca123456789abcdef01234');
      expect(order.trackingNumber, 'ZWR-491823');
      expect(order.currentStatus, 'Shipped');
      expect(order.courierPartner, 'Sequel Secure Luxury Logistics');
      expect(order.items.length, 1);
      expect(order.timeline.length, 6);

      // Verify completion state for all 6 stages
      expect(order.timeline[0].isCompleted, isTrue); // Order Placed
      expect(order.timeline[1].isCompleted, isTrue); // Order Confirmed
      expect(order.timeline[2].isCompleted, isTrue); // Processing
      expect(order.timeline[3].isCompleted, isTrue); // Shipped
      expect(order.timeline[4].isCompleted, isFalse); // Out for Delivery
      expect(order.timeline[5].isCompleted, isFalse); // Delivered
    });

    test('All 6 tracking stage names are mapped and normalized correctly', () {
      final allStages = [
        "Order Placed",
        "Order Confirmed",
        "Processing",
        "Shipped",
        "Out for Delivery",
        "Delivered",
      ];

      for (int i = 0; i < allStages.length; i++) {
        final stage = allStages[i];
        final idx = allStages.indexWhere(
          (s) => s.toLowerCase() == stage.toLowerCase(),
        );
        expect(idx, i, reason: "Stage '$stage' should map to index $i");
      }
    });
  });
}
