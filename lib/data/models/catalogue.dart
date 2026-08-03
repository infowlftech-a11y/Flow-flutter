import '../../core/constants.dart';
import '../../core/utils/doc_x.dart';

enum ServiceKind { rental, beachUse }

/// Station rental / beach-pass service (§5.5).
class StationService {
  const StationService({
    required this.id,
    required this.name,
    required this.price,
    this.description,
    this.unit,
    required this.kind,
  });

  final String id;
  final String name;
  final double price;
  final String? description;
  final String? unit;
  final ServiceKind kind;

  factory StationService.fromDoc(String id, Map<String, dynamic> d) {
    final rawKind = (d.str('kind') ?? d.str('type') ?? '').toLowerCase();
    return StationService(
      id: id,
      name: d.str('name') ?? 'Service',
      price: d.money('price') ?? 0,
      description: d.str('description'),
      unit: d.str('unit'),
      kind: rawKind == 'beach_use' || rawKind == 'beach'
          ? ServiceKind.beachUse
          : ServiceKind.rental,
    );
  }
}

class StationInstructor {
  const StationInstructor({
    required this.id,
    required this.name,
    this.level,
    this.rate,
    this.photoUrl,
  });

  final String id;
  final String name;
  final String? level;
  final double? rate;
  final String? photoUrl;

  factory StationInstructor.fromDoc(String id, Map<String, dynamic> d) =>
      StationInstructor(
        id: id,
        name: d.str('name') ?? 'Instructor',
        level: d.str('level'),
        rate: d.money('rate'),
        photoUrl: d.str('photoUrl'),
      );

  double get displayRate => rate ?? FlowConst.defaultDisplayRate;
}

class SafariTrip {
  const SafariTrip({
    required this.id,
    required this.hostId,
    required this.title,
    this.startDate,
    required this.price,
    required this.capacity,
    required this.bookedSeats,
    this.description,
    this.duration,
  });

  final String id;
  final String hostId;
  final String title;

  /// Local `YYYY-MM-DD`.
  final String? startDate;
  final double price;
  final int capacity;
  final int bookedSeats;
  final String? description;
  final String? duration;

  factory SafariTrip.fromDoc(String id, Map<String, dynamic> d) => SafariTrip(
        id: id,
        hostId: d.str('hostId') ?? '',
        title: d.str('title') ?? 'Expedition',
        startDate: d.str('startDate'),
        price: d.money('price') ?? 0,
        capacity: d.integer('capacity') ?? 0,
        bookedSeats: d.integer('bookedSeats') ?? 0,
        description: d.str('description'),
        duration: d.str('duration'),
      );

  int get seatsLeft => (capacity - bookedSeats).clamp(0, capacity);
  bool get isSoldOut => capacity > 0 && bookedSeats >= capacity;
  double get fillRatio =>
      capacity <= 0 ? 0 : (bookedSeats / capacity).clamp(0.0, 1.0);
}

/// The funnel every bookable thing passes through — transient, never
/// persisted (§5.5).
class BookingTarget {
  const BookingTarget({
    required this.providerId,
    required this.title,
    required this.rate,
    this.subtitle,
    this.imageUrl,
    this.unit = 'hour',
    this.bookingType = 'lesson',
    this.subTarget,
  });

  /// The uid owning the calendar.
  final String providerId;
  final String title;
  final double rate;
  final String? subtitle;
  final String? imageUrl;
  final String unit;
  final String bookingType;

  /// Instructor / service name inside a station.
  final String? subTarget;
}
