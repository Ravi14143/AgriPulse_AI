import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MandiPriceTab extends StatefulWidget {
  final String userId;
  const MandiPriceTab({super.key, required this.userId});

  @override
  State<MandiPriceTab> createState() => _MandiPriceTabState();
}

class _MandiPriceTabState extends State<MandiPriceTab> {
  final _formKey = GlobalKey<FormState>();

  String selectedCrop = 'soyabean';
  String selectedState = 'rajasthan';
  DateTime? fromDate;
  DateTime? toDate;

  bool isLoading = false;
  List<dynamic> mandiData = [];

  List<Map<String, dynamic>> todayCropRequests = [];
  List<dynamic> todayPrices = [];
  bool isTodayLoading = true;

  @override
  void initState() {
    super.initState();
    loadTodayCropRequests();
  }

  Future<void> loadTodayCropRequests() async {
    setState(() => isTodayLoading = true);
    try {
      // Step 1: Get user document to extract userId field
      final userDoc = await FirebaseFirestore.instance
          .collection('user')
          .doc(widget.userId)
          .get();

      if (!userDoc.exists) {
        debugPrint('User document not found for ID: ${widget.userId}');
        return;
      }

      final actualUserId = userDoc.data()?['userId'];
      if (actualUserId == null) {
        debugPrint('userId field missing in user document');
        return;
      }

      // Step 2: Use extracted userId field to query crops
      final snapshot = await FirebaseFirestore.instance
          .collection('crops')
          .where('userId', isEqualTo: actualUserId)
          .get();

      final crops = snapshot.docs
          .map((doc) => doc.data())
          .where((data) =>
              data['cropname'] != null &&
              data['cropstate'] != null &&
              data['cropname'].toString().isNotEmpty &&
              data['cropstate'].toString().isNotEmpty)
          .toList();

      todayCropRequests = crops.cast<Map<String, dynamic>>();
      fetchTodayPrices();
    } catch (e) {
      debugPrint('Error loading user crops: $e');
    }
  }

  Future<void> fetchTodayPrices() async {
    List<dynamic> results = [];
    final today = DateFormat('dd-MMM-yyyy')
        .format(DateTime.now().subtract(const Duration(days: 2)));

    for (var crop in todayCropRequests) {
      final cropName = crop['cropname'].toString().toLowerCase();
      final cropState = crop['cropstate'].toString().toLowerCase();

      final url = Uri.parse(
          'http://127.0.0.1:5000/mandi-prices?crop=$cropName&state=$cropState&from_date=$today&to_date=$today');

      try {
        final response = await http.get(url);
        if (response.statusCode == 200) {
          final List<dynamic> data = jsonDecode(response.body);
          results.addAll(data);
        }
      } catch (e) {
        debugPrint("Error fetching today's mandi price: $e");
      }
    }

    setState(() {
      todayPrices = results;
      isTodayLoading = false;
    });
  }

  Future<void> fetchMandiPrices() async {
    if (fromDate == null || toDate == null) return;

    final String formattedFrom = DateFormat('dd-MMM-yyyy').format(fromDate!);
    final String formattedTo = DateFormat('dd-MMM-yyyy').format(toDate!);

    final url = Uri.parse(
      'http://127.0.0.1:5000/mandi-prices?crop=$selectedCrop&state=$selectedState&from_date=$formattedFrom&to_date=$formattedTo',
    );

    setState(() => isLoading = true);

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() => mandiData = data);
      } else {
        debugPrint("Failed: ${response.body}");
      }
    } catch (e) {
      debugPrint("Error: $e");
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> selectDate(BuildContext context, bool isFromDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: fromDate ?? DateTime.now(),
      firstDate: DateTime(2022),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() {
        if (isFromDate) {
          fromDate = picked;
        } else {
          toDate = picked;
        }
      });
    }
  }

  Widget buildPriceBar(double min, double modal, double max) {
    final total = max - min;
    final modalPos = modal - min;
    final barWidth = MediaQuery.of(context).size.width * 0.7;

    return Row(
      children: [
        Text("₹$min", style: const TextStyle(color: Colors.red)),
        Expanded(
          child: Stack(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                height: 12,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Colors.red, Colors.yellow, Colors.green],
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              Positioned(
                left: total != 0
                    ? ((modalPos / total) * barWidth)
                        .clamp(0.0, barWidth - 12.0)
                    : 0.0,
                child: const Icon(Icons.circle, size: 12, color: Colors.black),
              ),
            ],
          ),
        ),
        Text("₹$max", style: const TextStyle(color: Colors.green)),
      ],
    );
  }

  Widget buildTodayPrices() {
    if (isTodayLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (todayPrices.isEmpty) {
      return const Text("No today's prices found.");
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "📊 Today’s Market Prices",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        ...todayPrices.map((item) {
          final min = double.tryParse(item['min_price']) ?? 0;
          final modal = double.tryParse(item['modal_price']) ?? 0;
          final max = double.tryParse(item['max_price']) ?? 0;

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 8),
            elevation: 4,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "📍 ${item['market']} (${item['district']})",
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                      "📦 Variety: ${item['variety']} | Grade: ${item['grade']}"),
                  const SizedBox(height: 8),
                  buildPriceBar(min, modal, max),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Text("📅 ${item['date']}"),
                  ),
                ],
              ),
            ),
          );
        }).toList()
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('🌾 Mandi Prices')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            buildTodayPrices(),
            const SizedBox(height: 20),
            Form(
              key: _formKey,
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    value: selectedCrop,
                    items: const [
                      DropdownMenuItem(
                        value: 'soyabean',
                        child: Text('Soyabean'),
                      ),
                    ],
                    onChanged: (val) => setState(() => selectedCrop = val!),
                    decoration: const InputDecoration(
                      labelText: 'Select Crop',
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: selectedState,
                    items: const [
                      DropdownMenuItem(
                        value: 'rajasthan',
                        child: Text('Rajasthan'),
                      ),
                    ],
                    onChanged: (val) => setState(() => selectedState = val!),
                    decoration: const InputDecoration(
                      labelText: 'Select State',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          readOnly: true,
                          controller: TextEditingController(
                            text: fromDate != null
                                ? DateFormat('dd-MMM-yyyy').format(fromDate!)
                                : '',
                          ),
                          decoration: const InputDecoration(
                            labelText: 'From Date ',
                          ),
                          onTap: () => selectDate(context, true),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          readOnly: true,
                          controller: TextEditingController(
                            text: toDate != null
                                ? DateFormat('dd-MMM-yyyy').format(toDate!)
                                : '',
                          ),
                          decoration: const InputDecoration(
                            labelText: 'To Date',
                          ),
                          onTap: () => selectDate(context, false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.search),
                    label: const Text("Get Prices"),
                    onPressed: fetchMandiPrices,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            isLoading
                ? const CircularProgressIndicator()
                : mandiData.isEmpty
                    ? const Text("No data found ")
                    : ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: mandiData.length,
                        itemBuilder: (context, index) {
                          final item = mandiData[index];

                          final min = double.tryParse(item['min_price']) ?? 0;
                          final modal =
                              double.tryParse(item['modal_price']) ?? 0;
                          final max = double.tryParse(item['max_price']) ?? 0;

                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 8),
                            elevation: 4,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "📍 ${item['market']} (${item['district']})",
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                      "📦 Variety: ${item['variety']} | Grade: ${item['grade']}"),
                                  const SizedBox(height: 8),
                                  buildPriceBar(min, modal, max),
                                  const SizedBox(height: 4),
                                  Align(
                                    alignment: Alignment.bottomRight,
                                    child: Text("📅 ${item['date']}"),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ],
        ),
      ),
    );
  }
}
