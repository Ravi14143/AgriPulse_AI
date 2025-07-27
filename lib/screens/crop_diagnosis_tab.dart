import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CropDiagnosisTab extends StatefulWidget {
  final String userId;

  const CropDiagnosisTab({super.key, required this.userId});

  @override
  State<CropDiagnosisTab> createState() => _CropDiagnosisTabState();
}

class _CropDiagnosisTabState extends State<CropDiagnosisTab> {
  XFile? _selectedImage;
  Uint8List? _webImageBytes;
  final TextEditingController _descController = TextEditingController();
  String _diagnosis = '';
  String _doctorName = '';
  String _doctorMobile = '';
  bool _loading = false;
  String _status = '';
  final FlutterTts _flutterTts = FlutterTts();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final String _backendUrl =
      'http://10.30.1.173:5000'; // Update to actual IP or domain in production
  final String _googleApiKey =
      'AIzaSyCL-1wDr3FKZmsjL4ui6tphOkdcdLjMv8Y'; // Replace with actual key

  final List<Map<String, String>> _supportedLanguages = [
    {'name': 'Hindi', 'code': 'hi'},
    {'name': 'Tamil', 'code': 'ta'},
    {'name': 'Telugu', 'code': 'te'},
    {'name': 'Bengali', 'code': 'bn'},
    {'name': 'Kannada', 'code': 'kn'},
  ];
  String _selectedLangCode = 'hi';

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _selectedImage = picked;
      });
      if (kIsWeb) {
        _webImageBytes = await picked.readAsBytes();
      }
    }
  }

  Future<String> _translateText(String text, String targetLangCode) async {
    final uri = Uri.parse(
        'https://translation.googleapis.com/language/translate/v2?key=$_googleApiKey');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'q': text, 'target': targetLangCode}),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['data']['translations'][0]['translatedText'];
    } else {
      throw Exception('Translation failed: ${response.body}');
    }
  }

  Future<void> _speakDiagnosis() async {
    await _flutterTts.setLanguage(_selectedLangCode);
    await _flutterTts.setPitch(1.0);
    await _flutterTts.speak(_diagnosis);
  }

  Future<void> _stopSpeech() async {
    await _flutterTts.stop();
  }

  Future<void> _submitForDiagnosis() async {
    if (_selectedImage == null) return;
    await _flutterTts.stop();

    setState(() {
      _loading = true;
      _diagnosis = '';
      _status = '📤 Sending image and description to backend...';
    });

    final uri = Uri.parse('$_backendUrl/diagnose');

    try {
      final request = http.MultipartRequest('POST', uri)
        ..fields['description'] = _descController.text;

      if (kIsWeb) {
        request.files.add(http.MultipartFile.fromBytes(
          'image',
          _webImageBytes!,
          filename: _selectedImage!.name,
          contentType: MediaType('image', 'jpeg'),
        ));
      } else {
        request.files.add(await http.MultipartFile.fromPath(
          'image',
          _selectedImage!.path,
          contentType: MediaType('image', 'jpeg'),
        ));
      }

      final streamedResponse = await request.send().timeout(
            const Duration(seconds: 30),
            onTimeout: () =>
                throw Exception("⏱️ Backend timeout. Check server connection."),
          );

      setState(() {
        _status = '🔬 Processing with backend...';
      });

      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        final rawDiagnosis = jsonResponse['diagnosis'] ?? 'No diagnosis found';
        _doctorName = jsonResponse['doctorName'] ?? 'AI Assistant';
        _doctorMobile = jsonResponse['doctorMobile'] ?? 'Not available';

        final translated =
            await _translateText(rawDiagnosis, _selectedLangCode);

        setState(() {
          _diagnosis = translated;
          _status = '✅ Diagnosis complete!';
        });
      } else {
        setState(() {
          _diagnosis = '❌ Error: ${response.reasonPhrase}';
          _status = '❗ Server responded with an error.';
        });
      }
    } catch (e) {
      setState(() {
        _diagnosis = '❌ Exception: ${e.toString()}';
        _status = '❗ Diagnosis request failed.';
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _saveDiagnosisToFirestore() async {
    if (_selectedImage == null || _diagnosis.isEmpty) return;

    final data = {
      'imagePath': _selectedImage!.path,
      'description': _descController.text,
      'diagnosisResult': _diagnosis,
      'doctorName': _doctorName,
      'doctorMobile': _doctorMobile,
      'userId': widget.userId,
      'timestamp': Timestamp.now(),
    };

    final diagnosisRef = _firestore
        .collection('user')
        .doc(widget.userId)
        .collection('diagnosis');

    try {
      await diagnosisRef.add(data);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Diagnosis saved to Firestore')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Failed to save: ${e.toString()}')),
      );
    }
  }

  @override
  void dispose() {
    _flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crop Diagnosis')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.image),
                  label: const Text('Upload Crop Image'),
                  onPressed: _pickImage,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(50),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _selectedLangCode,
                  decoration: InputDecoration(
                    labelText: 'Select Language',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: const Color(0xFFF6FAF2),
                  ),
                  items: _supportedLanguages.map((lang) {
                    return DropdownMenuItem<String>(
                      value: lang['code'],
                      child: Text(lang['name']!),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() => _selectedLangCode = value!);
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _descController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Optional description (symptoms, etc)',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: const Color(0xFFF6FAF2),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  icon: const Icon(Icons.science),
                  label: const Text('Diagnose'),
                  onPressed:
                      _selectedImage == null ? null : _submitForDiagnosis,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade800,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(50),
                  ),
                ),
                const SizedBox(height: 24),
                if (_loading)
                  Column(
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                      Text(_status, style: const TextStyle(fontSize: 16)),
                    ],
                  )
                else ...[
                  if (_status.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child:
                          Text(_status, style: const TextStyle(fontSize: 16)),
                    ),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_diagnosis.isEmpty)
                          const Text('Diagnosis report will appear here.',
                              style: TextStyle(fontSize: 16))
                        else ...[
                          MarkdownBody(
                            data: _diagnosis,
                            styleSheet:
                                MarkdownStyleSheet.fromTheme(Theme.of(context))
                                    .copyWith(p: const TextStyle(fontSize: 16)),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '👨‍⚕️ Diagnosed by: $_doctorName\n📞 Mobile: $_doctorMobile',
                            style: const TextStyle(
                              fontSize: 16,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.volume_up),
                                tooltip: 'Speak Diagnosis',
                                onPressed: _speakDiagnosis,
                              ),
                              IconButton(
                                icon: const Icon(Icons.stop),
                                tooltip: 'Stop Speech',
                                onPressed: _stopSpeech,
                              ),
                            ],
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.save),
                              label: const Text("Save"),
                              onPressed: _diagnosis.isEmpty
                                  ? null
                                  : _saveDiagnosisToFirestore,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ]
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
