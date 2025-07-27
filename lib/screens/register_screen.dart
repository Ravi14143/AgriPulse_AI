import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:csc_picker/csc_picker.dart';
import 'package:uuid/uuid.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _uuid = const Uuid();

  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _phone = TextEditingController();
  final _age = TextEditingController();
  final _zipcode = TextEditingController();

  String? _country, _state, _city;
  File? _profileImage;
  String? _profileImageUrl;
  bool _isLoading = false;

  Future<void> _pickImage() async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _profileImage = File(image.path);
      });
    }
  }

  Future<String?> _uploadImage(String userId) async {
    if (_profileImage == null) return null;
    try {
      final ref = FirebaseStorage.instance
          .ref('profile_images')
          .child('$userId.jpg');
      await ref.putFile(_profileImage!);
      final url = await ref.getDownloadURL();
      return url;
    } catch (e) {
      print('Image upload error: $e');
      return null;
    }
  }

  Future<bool> _checkIfNumberExists(String phone) async {
    final result = await FirebaseFirestore.instance
        .collection('user')
        .where('number', isEqualTo: int.parse(phone))
        .get();

    return result.docs.isNotEmpty;
  }

  bool _isValidPhone(String phone) {
    return RegExp(r'^\d{10}$').hasMatch(phone);
  }

  bool _isValidPassword(String password) {
    return RegExp(r'^(?=.*[A-Za-z])(?=.*\d)[A-Za-z\d]{8,}$').hasMatch(password);
  }

  bool _isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }

  Future<void> _registerUser() async {
    if (!_formKey.currentState!.validate() ||
        _country == null ||
        _state == null ||
        _city == null ||
        _profileImage == null) {
      _showError('Please complete all fields including image and location.');
      return;
    }

    if (!_isValidPhone(_phone.text.trim())) {
      _showError('Phone number must be exactly 10 digits.');
      return;
    }

    if (!_isValidPassword(_password.text.trim())) {
      _showError(
        'Password must be at least 8 characters and include letters and numbers.',
      );
      return;
    }

    if (!_isValidEmail(_email.text.trim())) {
      _showError('Please enter a valid email address.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final exists = await _checkIfNumberExists(_phone.text.trim());

      if (exists) {
        _showDialog(
          'Number Already Registered',
          'Please login or use another number.',
          redirectToLogin: true,
        );
        return;
      }

      final userId = _uuid.v4();
      final imageUrl = await _uploadImage(userId);
      _profileImageUrl = imageUrl;

      await FirebaseFirestore.instance.collection('user').doc(userId).set({
        'userId': userId,
        'name': _name.text.trim(),
        'mail': _email.text.trim(),
        'password': _password.text.trim(),
        'number': int.parse(_phone.text.trim()),
        'age': int.parse(_age.text.trim()),
        'country': _country,
        'state': _state,
        'city': _city,
        'zipcode': int.parse(_zipcode.text.trim()),
        'profile_image': imageUrl ?? '',
      });

      _showDialog(
        'Registration Successful',
        'You can now login.',
        redirectToLogin: true,
      );
    } catch (e) {
      _showError('Registration failed: ${e.toString()}');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showDialog(
    String title,
    String message, {
    bool redirectToLogin = false,
  }) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            child: const Text('OK'),
            onPressed: () {
              Navigator.pop(context);
              if (redirectToLogin) {
                Navigator.pushReplacementNamed(context, '/login');
              }
            },
          ),
        ],
      ),
    );
  }

  void _showError(String message) => _showDialog('Error', message);

  Widget _buildInput(
    TextEditingController ctrl,
    String label, {
    bool isPassword = false,
    bool isNumber = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        controller: ctrl,
        obscureText: isPassword,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        validator: (value) {
          if (value == null || value.isEmpty) return 'Please enter $label';
          if (label == 'Phone Number' && !_isValidPhone(value))
            return 'Enter 10-digit number';
          if (label == 'Password' && !_isValidPassword(value))
            return 'Min 8 chars with letters and numbers';
          if (label == 'Email' && !_isValidEmail(value))
            return 'Enter valid email';
          return null;
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Register'),
        centerTitle: true,
        backgroundColor: Colors.green.shade700,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              GestureDetector(
                onTap: _pickImage,
                child: CircleAvatar(
                  radius: 55,
                  backgroundColor: Colors.grey[300],
                  backgroundImage: _profileImage != null
                      ? FileImage(_profileImage!)
                      : (_profileImageUrl != null
                                ? NetworkImage(_profileImageUrl!)
                                : null)
                            as ImageProvider<Object>?,
                  child: _profileImage == null && _profileImageUrl == null
                      ? const Icon(Icons.add_a_photo, size: 30)
                      : null,
                ),
              ),
              const SizedBox(height: 16),
              _buildInput(_name, 'Full Name'),
              _buildInput(_email, 'Email'),
              _buildInput(_password, 'Password', isPassword: true),
              _buildInput(_phone, 'Phone Number', isNumber: true),
              _buildInput(_age, 'Age', isNumber: true),
              _buildInput(_zipcode, 'Zipcode', isNumber: true),

              const SizedBox(height: 12),
              CSCPicker(
                layout: Layout.vertical,
                onCountryChanged: (val) => setState(() => _country = val),
                onStateChanged: (val) => setState(() => _state = val),
                onCityChanged: (val) => setState(() => _city = val),
                showStates: true,
                showCities: true,
                flagState: CountryFlag.SHOW_IN_DROP_DOWN_ONLY,
              ),
              const SizedBox(height: 20),

              _isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton.icon(
                      onPressed: _registerUser,
                      icon: const Icon(Icons.person_add),
                      label: const Text('Register'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        backgroundColor: Colors.green,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
