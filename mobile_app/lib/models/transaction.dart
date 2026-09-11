/// Mirrors the API's TransactionCreate/TransactionOut + local-only sync
/// bookkeeping fields (clientTransactionId, synced).
class LocalTransaction {
  final String clientTransactionId; // stable id, used for /sync idempotency
  final int year;
  final int month;
  final DateTime date;
  final String type; // Expense | Free Money | Investment
  final String category;
  final String subcategory;
  final String item;
  final double amount;
  final String? classification;
  final String? notes;
  final bool synced;

  const LocalTransaction({
    required this.clientTransactionId,
    required this.year,
    required this.month,
    required this.date,
    required this.type,
    required this.category,
    required this.subcategory,
    required this.item,
    required this.amount,
    this.classification,
    this.notes,
    this.synced = false,
  });

  LocalTransaction copyWith({bool? synced}) => LocalTransaction(
        clientTransactionId: clientTransactionId,
        year: year,
        month: month,
        date: date,
        type: type,
        category: category,
        subcategory: subcategory,
        item: item,
        amount: amount,
        classification: classification,
        notes: notes,
        synced: synced ?? this.synced,
      );

  Map<String, Object?> toDbMap() => {
        'client_transaction_id': clientTransactionId,
        'year': year,
        'month': month,
        'date': date.toIso8601String().substring(0, 10),
        'type': type,
        'category': category,
        'subcategory': subcategory,
        'item': item,
        'amount': amount,
        'classification': classification,
        'notes': notes,
        'synced': synced ? 1 : 0,
      };

  static LocalTransaction fromDbMap(Map<String, Object?> row) => LocalTransaction(
        clientTransactionId: row['client_transaction_id'] as String,
        year: row['year'] as int,
        month: row['month'] as int,
        date: DateTime.parse(row['date'] as String),
        type: row['type'] as String,
        category: row['category'] as String,
        subcategory: row['subcategory'] as String,
        item: row['item'] as String,
        amount: (row['amount'] as num).toDouble(),
        classification: row['classification'] as String?,
        notes: row['notes'] as String?,
        synced: (row['synced'] as int) == 1,
      );

  /// Shape expected by one entry in POST /api/v1/sync's `operations` array.
  Map<String, Object?> toSyncOperation() => {
        'operation': 'create_transaction',
        'client_transaction_id': clientTransactionId,
        'year': year,
        'month': month,
        'date': date.toIso8601String().substring(0, 10),
        'type': type,
        'category': category,
        'subcategory': subcategory,
        'item': item,
        'amount': amount,
        if (classification != null) 'classification': classification,
        if (notes != null) 'notes': notes,
      };
}
