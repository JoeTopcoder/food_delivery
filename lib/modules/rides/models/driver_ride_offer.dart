import 'ride_request.dart';
import 'ride_driver_request.dart';

/// Combines a pending driver request with the full ride details.
/// Delivered atomically via streamDriverRideOffers so the card always
/// has the data it needs without a separate async fetch.
class DriverRideOffer {
  final RideDriverRequest request;
  final RideRequest? ride;

  const DriverRideOffer({required this.request, this.ride});

  String get rideId => request.rideId;
  int get secondsUntilExpiry => request.secondsUntilExpiry;
  bool get isExpired => request.isExpired;
}
