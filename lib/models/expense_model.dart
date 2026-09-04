class ExpenseModel {
  final String id;
  final String restaurantId;
  final String expenseName;
  final double amount;
  final String paymentMode; // 'CASH' या 'UPI'
  final DateTime createdAt;

  const ExpenseModel({
    required this.id,
    required this.restaurantId,
    required this.expenseName,
    required this.amount,
    this.paymentMode = 'CASH',
    required this.createdAt,
  });

  factory ExpenseModel.fromMap(Map<String, dynamic> map) {
    return ExpenseModel(
      id: map['id']?.toString() ?? '',
      restaurantId: map['restaurant_id']?.toString() ?? '',
      expenseName: map['expense_name'] ?? '',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      paymentMode: map['payment_mode'] ?? 'CASH',
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'restaurant_id': restaurantId,
      'expense_name': expenseName,
      'amount': amount,
      'payment_mode': paymentMode,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
