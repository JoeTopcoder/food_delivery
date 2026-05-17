import 'package:flutter/material.dart';

class RideDriverApprovalPage extends StatelessWidget {
  const RideDriverApprovalPage({super.key});

  @override
  Widget build(BuildContext context) {
    // TODO: Connect to driver approval provider
    return Scaffold(
      appBar: AppBar(title: const Text('Driver Approvals'), elevation: 0),
      body: ListView.builder(
        itemCount: 10, // TODO: Replace with real data
        itemBuilder: (context, index) => ListTile(
          leading: const Icon(Icons.person),
          title: Text('Driver #$index'),
          subtitle: const Text('Pending Approval'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.check, color: Colors.green),
                onPressed: () {},
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.red),
                onPressed: () {},
              ),
            ],
          ),
        ),
      ),
    );
  }
}
