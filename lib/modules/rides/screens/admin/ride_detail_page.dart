import 'package:flutter/material.dart';

class RideDetailPage extends StatelessWidget {
  final String rideId;
  const RideDetailPage({super.key, required this.rideId});

  @override
  Widget build(BuildContext context) {
    // TODO: Connect to ride detail provider
    return Scaffold(
      appBar: AppBar(title: const Text('Ride Details'), elevation: 0),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ride ID: $rideId'),
            // ...ride details...
          ],
        ),
      ),
    );
  }
}
