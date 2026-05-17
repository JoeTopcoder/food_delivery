import 'package:flutter/material.dart';

class RideReportsPage extends StatelessWidget {
  const RideReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    // TODO: Connect to reports provider
    return Scaffold(
      appBar: AppBar(title: const Text('Ride Reports'), elevation: 0),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Daily/Weekly Revenue'),
            // ...charts and reports...
          ],
        ),
      ),
    );
  }
}
