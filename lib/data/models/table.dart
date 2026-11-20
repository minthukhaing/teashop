library teashop_pos.data.models.table;

import '../../core/utils/myanmar_text.dart';

/// A single dining table managed by the Admin Host.
///
/// The Admin owns the canonical list of tables in the local SQLite database
/// and exposes it to Waiter/Kitchen clients through the Shelf API
/// (`GET /api/tables`).  Waiters therefore always see the exact set of active
/// tables configured by the Admin, rather than a hardcoded local count.
///
/// All free-text fields are normalised to Unicode **NFC** so Burmese table
/// labels store one canonical form and match reliably across clients.
class TableModel {
  const TableModel({
    this.id,
    required this.number,
    this.capacity = 4,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  /// Primary key (assigned by SQLite on insert).
  final int? id;

  /// Canonical table label shown to staff, e.g. `T1`, `5`, `ầ fenêtre` ...
  /// Must be unique across all tables.
  final String number;

  /// Number of seats the table accommodates.
  final int capacity;

  /// Whether the table is available for service.  Inactive tables are hidden
  /// from the Waiter tables grid but kept in the database for history.
  final bool isActive;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Column-friendly map for SQLite (snake_case keys).
  Map<String, Object?> toMap() {
    return {
      'id': id,
      'number': MyanmarText.normalize(number.trim()),
      'capacity': capacity,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  factory TableModel.fromMap(Map<String, Object?> map) {
    return TableModel(
      id: map['id'] as int?,
      number: MyanmarText.normalize(map['number'] as String? ?? ''),
      capacity: (map['capacity'] as num?)?.toInt() ?? 4,
      isActive: (map['is_active'] as int?)?.toInt() == 1,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? ''),
      updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? ''),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'number': number,
        'capacity': capacity,
        'isActive': isActive,
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
      };

  factory TableModel.fromJson(Map<String, dynamic> json) => TableModel(
        id: json['id'] as int?,
        number: json['number'] as String? ?? '',
        capacity: (json['capacity'] as num?)?.toInt() ?? 4,
        isActive: json['isActive'] as bool? ?? true,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
      );

  TableModel copyWith({
    int? id,
    String? number,
    int? capacity,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool clearCreatedAt = false,
    bool clearUpdatedAt = false,
  }) {
    return TableModel(
      id: id ?? this.id,
      number: number ?? this.number,
      capacity: capacity ?? this.capacity,
      isActive: isActive ?? this.isActive,
      createdAt: clearCreatedAt ? null : createdAt ?? this.createdAt,
      updatedAt: clearUpdatedAt ? null : updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() => 'TableModel(id: $id, number: $number, active: $isActive)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TableModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          number == other.number;

  @override
  int get hashCode => Object.hash(id, number);
}
