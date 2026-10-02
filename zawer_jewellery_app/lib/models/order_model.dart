class TrackingStep {
  final String status;
  final String title;
  final String description;
  final String location;
  final DateTime? timestamp;
  final bool isCompleted;

  TrackingStep({
    required this.status,
    required this.title,
    required this.description,
    required this.location,
    this.timestamp,
    required this.isCompleted,
  });

  factory TrackingStep.fromJson(Map<String, dynamic> json) {
    DateTime? parsedTime;
    if (json["timestamp"] != null) {
      try {
        parsedTime = DateTime.parse(json["timestamp"].toString()).toLocal();
      } catch (_) {}
    }

    return TrackingStep(
      status: json["status"]?.toString() ?? "",
      title: json["title"]?.toString() ?? "",
      description: json["description"]?.toString() ?? "",
      location: json["location"]?.toString() ?? "ZAWER Vault",
      timestamp: parsedTime,
      isCompleted: json["isCompleted"] == true,
    );
  }
}

class OrderItemModel {
  final String productId;
  final String name;
  final String image;
  final double price;
  final int quantity;

  OrderItemModel({
    required this.productId,
    required this.name,
    required this.image,
    required this.price,
    required this.quantity,
  });

  factory OrderItemModel.fromJson(Map<String, dynamic> json) {
    return OrderItemModel(
      productId: json["productId"]?.toString() ?? "",
      name: json["name"]?.toString() ?? "",
      image: json["image"]?.toString() ?? "",
      price: (json["price"] as num?)?.toDouble() ?? 0.0,
      quantity: (json["quantity"] as num?)?.toInt() ?? 1,
    );
  }
}

class OrderTrackingModel {
  final String orderId;
  final String trackingNumber;
  final String currentStatus;
  final String courierPartner;
  final String currentLocation;
  final DateTime? estimatedDelivery;
  final String aiDeliveryInsight;
  final String customerName;
  final String address;
  final String phone;
  final double totalAmount;
  final DateTime? createdAt;
  final List<OrderItemModel> items;
  final List<TrackingStep> timeline;

  OrderTrackingModel({
    required this.orderId,
    required this.trackingNumber,
    required this.currentStatus,
    required this.courierPartner,
    required this.currentLocation,
    this.estimatedDelivery,
    required this.aiDeliveryInsight,
    required this.customerName,
    required this.address,
    required this.phone,
    required this.totalAmount,
    this.createdAt,
    required this.items,
    required this.timeline,
  });

  factory OrderTrackingModel.fromJson(Map<String, dynamic> json) {
    DateTime? estDate;
    if (json["estimatedDelivery"] != null) {
      try {
        estDate = DateTime.parse(json["estimatedDelivery"].toString()).toLocal();
      } catch (_) {}
    }

    DateTime? createdDate;
    if (json["createdAt"] != null) {
      try {
        createdDate = DateTime.parse(json["createdAt"].toString()).toLocal();
      } catch (_) {}
    }

    final rawItems = (json["items"] as List?) ?? [];
    final itemsList = rawItems
        .whereType<Map>()
        .map((e) => OrderItemModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    final rawTimeline = (json["timeline"] as List?) ?? [];
    final timelineList = rawTimeline
        .whereType<Map>()
        .map((e) => TrackingStep.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    return OrderTrackingModel(
      orderId: json["orderId"]?.toString() ?? json["_id"]?.toString() ?? "",
      trackingNumber: json["trackingNumber"]?.toString() ?? "ZWR-TRACKING",
      currentStatus: json["currentStatus"]?.toString() ?? json["status"]?.toString() ?? "Order Placed",
      courierPartner: json["courierPartner"]?.toString() ?? "Sequel Secure Luxury Logistics",
      currentLocation: json["currentLocation"]?.toString() ?? "In Transit",
      estimatedDelivery: estDate,
      aiDeliveryInsight: json["aiDeliveryInsight"]?.toString() ?? "Package under active security monitoring.",
      customerName: json["customerName"]?.toString() ?? "",
      address: json["address"]?.toString() ?? "",
      phone: json["phone"]?.toString() ?? "",
      totalAmount: (json["totalAmount"] as num?)?.toDouble() ?? 0.0,
      createdAt: createdDate,
      items: itemsList,
      timeline: timelineList,
    );
  }
}
