import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'login_screen.dart';
import 'package:intl/intl.dart';

class ProfileTab extends StatefulWidget {
  final String userId;

  const ProfileTab({super.key, required this.userId});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  final _firestore = FirebaseFirestore.instance;
  bool _isEditing = false;
  bool _isLoading = true;

  Map<String, dynamic>? _userData;
  List<Map<String, dynamic>> _cropList = [];
  List<Map<String, dynamic>> _diagnosisList = [];
  List<Map<String, dynamic>> _schemeList = [];

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _mailController = TextEditingController();
  final TextEditingController _numberController = TextEditingController();
  final TextEditingController _userIdController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadCrops();
    _loadDiagnosisReports();
    _loadAppliedSchemes();
  }

  void _loadUserData() async {
    final doc = await _firestore.collection('user').doc(widget.userId).get();
    if (doc.exists) {
      _userData = doc.data()!;
      _userData!['userId'] = doc.id;
      _nameController.text = _userData!['name'] ?? '';
      _mailController.text = _userData!['mail'] ?? '';
      _numberController.text = _userData!['number'].toString();
      _userIdController.text = _userData!['userId'] ?? '';
    }
    setState(() => _isLoading = false);
  }

  void _loadCrops() async {
    final cropSnapshot = await _firestore
        .collection('crops')
        .where('userId', isEqualTo: widget.userId)
        .get();
    _cropList = cropSnapshot.docs.map((doc) {
      return {'id': doc.id, ...doc.data()};
    }).toList();
    setState(() {});
  }

  void _loadDiagnosisReports() async {
    final snapshot = await _firestore
        .collection('diagnosis')
        .where('userId', isEqualTo: widget.userId)
        .get();
    _diagnosisList = snapshot.docs.map((doc) {
      return {'id': doc.id, ...doc.data()};
    }).toList();
    setState(() {});
  }

  void _loadAppliedSchemes() async {
    final snapshot = await _firestore
        .collection('GovernmentSchemes')
        .where('userId', isEqualTo: widget.userId)
        .get();
    _schemeList = snapshot.docs.map((doc) {
      return {'id': doc.id, ...doc.data()};
    }).toList();
    setState(() {});
  }

  void _updateProfile() async {
    await _firestore.collection('user').doc(widget.userId).update({
      'name': _nameController.text,
      'mail': _mailController.text,
      'number': int.tryParse(_numberController.text),
      'userId': _userIdController.text,
    });
    setState(() => _isEditing = false);
    _loadUserData();
  }

  void _logout() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _showCropDialog({Map<String, dynamic>? crop}) {
    final TextEditingController nameCtrl =
        TextEditingController(text: crop?['cropname'] ?? '');
    final TextEditingController locationCtrl =
        TextEditingController(text: crop?['croplocation'] ?? '');
    final TextEditingController quantityCtrl =
        TextEditingController(text: crop?['cropquantity']?.toString() ?? '');
    final TextEditingController ageCtrl =
        TextEditingController(text: crop?['cropage']?.toString() ?? '');
    final TextEditingController periodCtrl =
        TextEditingController(text: crop?['cropperiod'] ?? '');
    final TextEditingController startCtrl =
        TextEditingController(text: crop?['cropstartdate'] ?? '');
    final TextEditingController endCtrl =
        TextEditingController(text: crop?['cropenddate'] ?? '');

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(crop == null ? 'Add Crop' : 'Edit Crop'),
        content: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Crop Name')),
              TextField(
                  controller: locationCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Crop Location')),
              TextField(
                  controller: quantityCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Crop Quantity (acres)'),
                  keyboardType: TextInputType.number),
              TextField(
                  controller: ageCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Crop Age (months)'),
                  keyboardType: TextInputType.number),
              TextField(
                  controller: periodCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Crop Period (months)')),
              TextField(
                  controller: startCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Start Date (dd/mm/yyyy)')),
              TextField(
                  controller: endCtrl,
                  decoration: const InputDecoration(
                      labelText: 'End Date (dd/mm/yyyy)')),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final data = {
                'cropname': nameCtrl.text,
                'croplocation': locationCtrl.text,
                'cropquantity': int.tryParse(quantityCtrl.text) ?? 0,
                'cropage': int.tryParse(ageCtrl.text) ?? 0,
                'cropperiod': periodCtrl.text,
                'cropstartdate': startCtrl.text,
                'cropenddate': endCtrl.text,
                'userId': widget.userId,
              };
              final cropsRef = _firestore.collection('crops');
              if (crop == null) {
                await cropsRef.add(data);
              } else {
                await cropsRef.doc(crop['id']).update(data);
              }
              Navigator.pop(context);
              _loadCrops();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  String _formatDate(dynamic value) {
    if (value is Timestamp) {
      return DateFormat('yyyy-MM-dd').format(value.toDate());
    }
    return value?.toString() ?? 'Unknown';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile & History'),
        actions: [
          IconButton(
            icon: Icon(_isEditing ? Icons.save : Icons.edit),
            onPressed: () {
              if (_isEditing) {
                _updateProfile();
              } else {
                setState(() => _isEditing = true);
              }
            },
          ),
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCropDialog(),
        child: const Icon(Icons.add),
        tooltip: 'Add Crop',
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CircleAvatar(radius: 50, child: Icon(Icons.person, size: 50)),
            const SizedBox(height: 20),
            TextField(
                controller: _nameController,
                enabled: _isEditing,
                decoration: const InputDecoration(labelText: 'Name')),
            TextField(
                controller: _mailController,
                enabled: _isEditing,
                decoration: const InputDecoration(labelText: 'Email')),
            TextField(
                controller: _numberController,
                enabled: _isEditing,
                decoration: const InputDecoration(labelText: 'Phone Number'),
                keyboardType: TextInputType.number),
            const SizedBox(height: 10),
            Text('User ID: ${_userData?['userId'] ?? 'N/A'}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 30),
            const Divider(height: 32),
            Text('Past Diagnosis Reports',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (_diagnosisList.isEmpty)
              const Text('No diagnosis reports found.')
            else
              ..._diagnosisList.map((report) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                      '– ${report['title'] ?? 'Untitled'} on ${_formatDate(report['date'])}'),
                );
              }),
            const SizedBox(height: 24),
            Text('Applied Schemes & Sales History',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (_schemeList.isEmpty)
              const Text('No schemes applied yet.')
            else
              ..._schemeList.map((scheme) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                      '– ${scheme['name'] ?? 'Unnamed Scheme'} applied on ${_formatDate(scheme['date'])}'),
                );
              }),
            const SizedBox(height: 24),
            Text('Crop Details', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (_cropList.isEmpty)
              const Text('No crop details found.')
            else
              ..._cropList.map((crop) {
                return Card(
                  child: ListTile(
                    title: Text(crop['cropname'] ?? 'Unnamed Crop'),
                    subtitle: Text(
                        'Location: ${crop['croplocation']}, Qty: ${crop['cropquantity']}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () => _showCropDialog(crop: crop),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
