import 'package:flutter/material.dart';
import 'crop_diagnosis_tab.dart';
import 'mandi_price_tab.dart';
import 'schemes_tab.dart';
import 'profile_tab.dart';

class HomeScreen extends StatefulWidget {
  final String userId;

  const HomeScreen({super.key, required this.userId});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final _tabs = [
      CropDiagnosisTab(userId: widget.userId),
      MandiPriceTab(userId: widget.userId),
      SchemesTab(userId: widget.userId),
      ProfileTab(userId: widget.userId),
    ];

    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _tabs[_currentIndex],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.camera_alt), label: 'Diagnosis'),
          NavigationDestination(
              icon: Icon(Icons.price_change), label: 'Market'),
          NavigationDestination(icon: Icon(Icons.rule), label: 'Schemes'),
          NavigationDestination(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
