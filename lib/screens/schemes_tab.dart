import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class SchemesTab extends StatefulWidget {
  final String userId;
  const SchemesTab({super.key, required this.userId});

  @override
  State<SchemesTab> createState() => _SchemesTabState();
}

class _SchemesTabState extends State<SchemesTab> {
  List<Map<String, dynamic>> schemes = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    loadSchemes();
  }

  Future<void> loadSchemes() async {
    await Future.delayed(const Duration(seconds: 1));
    schemes = [
      {
        'id': 'scheme1',
        'name': 'Crop Insurance Scheme',
        'description':
            'Insurance coverage for crop failure due to natural disasters.',
        'startDate': '2024-01-01',
        'endDate': '2025-01-01',
        'link': 'https://example.com/scheme1',
      },
    ];
    setState(() => isLoading = false);
  }

  Future<void> sendPushNotification(
      String token, String title, String body) async {
    const String serverKey =
        ''; // get from Firebase > Project Settings > Cloud Messaging

    try {
      final response = await http.post(
        Uri.parse('https://fcm.googleapis.com/fcm/send'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'key=$serverKey',
        },
        body: jsonEncode({
          'to': token,
          'notification': {
            'title': title,
            'body': body,
          },
        }),
      );
      if (response.statusCode != 200) {
        debugPrint('Failed to send FCM: ${response.body}');
      }
    } catch (e) {
      debugPrint('Notification error: $e');
    }
  }

  Future<void> openSchemeLink(Map<String, dynamic> scheme) async {
    final url = Uri.parse(scheme['link']);
    if (!await canLaunchUrl(url)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Could not launch the scheme URL.')),
      );
      return;
    }

    await launchUrl(url);

    final applied = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apply Confirmation'),
        content: const Text('Did you apply for this scheme?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('No')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Yes')),
        ],
      ),
    );

    if (applied == true) {
      await FirebaseFirestore.instance.collection('GovernmentScheme').add({
        'applied': true,
        'nameOfScheme': scheme['name'],
        'schemeStart': Timestamp.fromDate(DateTime.parse(scheme['startDate'])),
        'schemeEnd': Timestamp.fromDate(DateTime.parse(scheme['endDate'])),
        'userId': widget.userId,
      });

      // Get user's FCM token from Firestore
      final userDoc = await FirebaseFirestore.instance
          .collection('user')
          .where('userId', isEqualTo: widget.userId)
          .limit(1)
          .get();

      final fcmToken = userDoc.docs.first.data()['fcmToken'];
      if (fcmToken != null) {
        await sendPushNotification(
          fcmToken,
          '🎉 Scheme Application Successful',
          'You applied for "${scheme['name']}".',
        );
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ "${scheme['name']}" marked as applied.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Government Schemes')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: schemes.length,
              itemBuilder: (context, index) {
                final scheme = schemes[index];
                return Card(
                  margin: const EdgeInsets.all(12),
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(scheme['name'],
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Text(scheme['description']),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text("Start: ${scheme['startDate']}"),
                            Text("End: ${scheme['endDate']}"),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton.icon(
                            onPressed: () => openSchemeLink(scheme),
                            icon: const Icon(Icons.open_in_new),
                            label: const Text("Apply Now"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade600,
                            ),
                          ),
                        )
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
