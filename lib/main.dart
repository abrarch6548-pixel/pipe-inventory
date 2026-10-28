import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

void main() {
  runApp(const PipeStoreApp());
}

class PipeStoreApp extends StatelessWidget {
  const PipeStoreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pipe Store Inventory',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E3A8A),
          primary: const Color(0xFF1E3A8A),
          secondary: const Color(0xFFEA580C),
        ),
      ),
      home: const MainInventoryScreen(),
    );
  }
}

class MainInventoryScreen extends StatefulWidget {
  const MainInventoryScreen({super.key});
  @override
  State<MainInventoryScreen> createState() => _MainInventoryScreenState();
}

class _MainInventoryScreenState extends State<MainInventoryScreen> {
  int _navIndex = 0;
  List<Map<String, dynamic>> transactions = [];
  List<String> locations = ['Yard 1', 'Yard 2', 'Warehouse A', 'Main Rack'];
  List<String> jpNames = ['JP-Alpha', 'JP-Beta', 'JP-North', 'JP-Pipeline-01'];
  List<String> suppliers = ['Steel Mills Corp', 'National Tubes Ltd', 'Atlas Piping'];

  final List<String> categories = [
    'Bare Pipe', 'Bare Bend', 'Painting Bend', 'Painting Pipe',
    '3LPP Pipe', '3LPP Bend', 'Spool', 'Cut Piece'
  ];

  final List<String> coatingOptions = [
    'Internal Coated', 'Without Internal Coating'
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/pipe_inventory_data.json');
  }

  Future<void> _loadData() async {
    try {
      final file = await _getFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final data = jsonDecode(content);
        setState(() {
          transactions = List<Map<String, dynamic>>.from(data['transactions'] ?? []);
          if (data['locations'] != null) locations = List<String>.from(data['locations']);
          if (data['jpNames'] != null) jpNames = List<String>.from(data['jpNames']);
          if (data['suppliers'] != null) suppliers = List<String>.from(data['suppliers']);
        });
      }
    } catch (_) {}
  }

  Future<void> _saveData() async {
    try {
      final file = await _getFile();
      final payload = {
        'transactions': transactions,
        'locations': locations,
        'jpNames': jpNames,
        'suppliers': suppliers,
      };
      await file.writeAsString(jsonEncode(payload));
    } catch (_) {}
  }

  double _getStock(String size, String grade, String sch, String cat, String coating) {
    double total = 0;
    for (var t in transactions) {
      if (t['pipeSize'] == size &&
          t['pipeGrade'] == grade &&
          t['pipeSch'] == sch &&
          t['category'] == cat &&
          t['internalCoating'] == coating) {
        double qty = (t['quantity'] as num).toDouble();
        if (t['type'] == 'RECEIVE') total += qty;
        if (t['type'] == 'ISSUE') total -= qty;
      }
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pipe Store Inventory', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: const Color(0xFF1E3A8A),
      ),
      body: _buildCurrentScreen(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _navIndex,
        onDestinationSelected: (i) => setState(() => _navIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.download), label: 'Receive'),
          NavigationDestination(icon: Icon(Icons.upload), label: 'Issue'),
          NavigationDestination(icon: Icon(Icons.inventory_2), label: 'Stock'),
          NavigationDestination(icon: Icon(Icons.tune), label: 'Manage'),
        ],
      ),
    );
  }

  Widget _buildCurrentScreen() {
    if (_navIndex == 0) return _buildDashboard();
    if (_navIndex == 1) return _buildReceiving();
    if (_navIndex == 2) return _buildIssuing();
    if (_navIndex == 3) return _buildStock();
    return _buildManage();
  }

  Widget _buildDashboard() {
    double received = 0;
    double issued = 0;
    for (var t in transactions) {
      double q = (t['quantity'] as num).toDouble();
      if (t['type'] == 'RECEIVE') received += q;
      if (t['type'] == 'ISSUE') issued += q;
    }
    double balance = received - issued;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Inventory Overview', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Card(
          color: Colors.blue.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Current Balance in Store', style: TextStyle(color: Colors.grey)),
                Text('$balance Qty', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A))),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Card(
                color: Colors.green.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Total Received', style: TextStyle(color: Colors.grey)),
                      Text('$received', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green)),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: Card(
                color: Colors.orange.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Total Issued', style: TextStyle(color: Colors.grey)),
                      Text('$issued', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.orange)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Text('Recent Transactions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ...transactions.reversed.take(5).map((t) => ListTile(
          leading: Icon(t['type'] == 'RECEIVE' ? Icons.arrow_downward : Icons.arrow_upward, color: t['type'] == 'RECEIVE' ? Colors.green : Colors.orange),
          title: Text('${t['category']} (${t['pipeSize']})'),
          subtitle: Text('Qty: ${t['quantity']} | Date: ${t['date']}'),
          trailing: Text(t['type'], style: TextStyle(fontWeight: FontWeight.bold, color: t['type'] == 'RECEIVE' ? Colors.green : Colors.orange)),
        )),
      ],
    );
  }

  Widget _buildReceiving() {
    final serialCtrl = TextEditingController();
    final sizeCtrl = TextEditingController();
    final gradeCtrl = TextEditingController();
    final schCtrl = TextEditingController();
    final qtyCtrl = TextEditingController();
    final remarksCtrl = TextEditingController();
    String cat = categories.first;
    String coat = coatingOptions.first;
    String supp = suppliers.isNotEmpty ? suppliers.first : 'Supplier 1';

    return StatefulBuilder(
      builder: (context, setSub) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Receive Pipes Into Store', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(controller: serialCtrl, decoration: const InputDecoration(labelText: 'Serial Number / Pipe ID')),
            TextField(controller: sizeCtrl, decoration: const InputDecoration(labelText: 'Pipe Size (e.g., 24")')),
            TextField(controller: gradeCtrl, decoration: const InputDecoration(labelText: 'Pipe Grade (e.g., X65)')),
            TextField(controller: schCtrl, decoration: const InputDecoration(labelText: 'Pipe SCH (e.g., SCH 80)')),
            DropdownButtonFormField<String>(
              value: cat,
              items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setSub(() => cat = v!),
              decoration: const InputDecoration(labelText: 'Category'),
            ),
            DropdownButtonFormField<String>(
              value: coat,
              items: coatingOptions.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setSub(() => coat = v!),
              decoration: const InputDecoration(labelText: 'Internal Coating Type'),
            ),
            TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity Received')),
            DropdownButtonFormField<String>(
              value: supp,
              items: suppliers.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (v) => setSub(() => supp = v!),
              decoration: const InputDecoration(labelText: 'Supplier'),
            ),
            TextField(controller: remarksCtrl, decoration: const InputDecoration(labelText: 'Remarks / Heat No')),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A8A)),
              onPressed: () {
                if (qtyCtrl.text.isEmpty || sizeCtrl.text.isEmpty) return;
                transactions.add({
                  'id': const Uuid().v4(),
                  'type': 'RECEIVE',
                  'serial': serialCtrl.text,
                  'pipeSize': sizeCtrl.text,
                  'pipeGrade': gradeCtrl.text,
                  'pipeSch': schCtrl.text,
                  'category': cat,
                  'internalCoating': coat,
                  'quantity': double.parse(qtyCtrl.text),
                  'entity': supp,
                  'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
                  'remarks': remarksCtrl.text,
                });
                _saveData();
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pipes Received Successfully!')));
              },
              child: const Text('SUBMIT RECEIVING', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildIssuing() {
    final serialCtrl = TextEditingController();
    final sizeCtrl = TextEditingController();
    final gradeCtrl = TextEditingController();
    final schCtrl = TextEditingController();
    final qtyCtrl = TextEditingController();
    final personCtrl = TextEditingController();
    String cat = categories.first;
    String coat = coatingOptions.first;
    String loc = locations.isNotEmpty ? locations.first : 'Yard';
    String jp = jpNames.isNotEmpty ? jpNames.first : 'JP-1';

    return StatefulBuilder(
      builder: (context, setSub) {
        double currentStock = _getStock(sizeCtrl.text, gradeCtrl.text, schCtrl.text, cat, coat);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Issue Pipes Out of Store', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Stock Available: $currentStock', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
            const SizedBox(height: 8),
            TextField(controller: serialCtrl, decoration: const InputDecoration(labelText: 'Serial Number / Pipe ID')),
            TextField(controller: sizeCtrl, decoration: const InputDecoration(labelText: 'Pipe Size'), onChanged: (_) => setSub(() {})),
            TextField(controller: gradeCtrl, decoration: const InputDecoration(labelText: 'Pipe Grade'), onChanged: (_) => setSub(() {})),
            TextField(controller: schCtrl, decoration: const InputDecoration(labelText: 'Pipe SCH'), onChanged: (_) => setSub(() {})),
            DropdownButtonFormField<String>(
              value: cat,
              items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setSub(() => cat = v!),
              decoration: const InputDecoration(labelText: 'Category'),
            ),
            DropdownButtonFormField<String>(
              value: coat,
              items: coatingOptions.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setSub(() => coat = v!),
              decoration: const InputDecoration(labelText: 'Internal Coating'),
            ),
            TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity to Issue')),
            TextField(controller: personCtrl, decoration: const InputDecoration(labelText: 'Issued To / Person Name')),
            DropdownButtonFormField<String>(
              value: loc,
              items: locations.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
              onChanged: (v) => setSub(() => loc = v!),
              decoration: const InputDecoration(labelText: 'Destination Location'),
            ),
            DropdownButtonFormField<String>(
              value: jp,
              items: jpNames.map((j) => DropdownMenuItem(value: j, child: Text(j))).toList(),
              onChanged: (v) => setSub(() => jp = v!),
              decoration: const InputDecoration(labelText: 'JP Name'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEA580C)),
              onPressed: () {
                double req = double.tryParse(qtyCtrl.text) ?? 0;
                if (req <= 0) return;
                if (req > currentStock) {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Insufficient Stock', style: TextStyle(color: Colors.red)),
                      content: Text('Cannot issue $req pipes. Only $currentStock available in store.'),
                      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
                    ),
                  );
                  return;
                }
                transactions.add({
                  'id': const Uuid().v4(),
                  'type': 'ISSUE',
                  'serial': serialCtrl.text,
                  'pipeSize': sizeCtrl.text,
                  'pipeGrade': gradeCtrl.text,
                  'pipeSch': schCtrl.text,
                  'category': cat,
                  'internalCoating': coat,
                  'quantity': req,
                  'entity': personCtrl.text,
                  'location': loc,
                  'jpName': jp,
                  'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
                });
                _saveData();
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pipes Issued Successfully!')));
              },
              child: const Text('SUBMIT ISSUING', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStock() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Current Stock Balances', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        ...categories.map((c) {
          return ExpansionTile(
            title: Text(c, style: const TextStyle(fontWeight: FontWeight.bold)),
            children: coatingOptions.map((coat) {
              double bal = 0;
              for (var t in transactions) {
                if (t['category'] == c && t['internalCoating'] == coat) {
                  double q = (t['quantity'] as num).toDouble();
                  if (t['type'] == 'RECEIVE') bal += q;
                  if (t['type'] == 'ISSUE') bal -= q;
                }
              }
              return ListTile(
                title: Text(coat),
                trailing: Text('$bal Qty', style: TextStyle(fontWeight: FontWeight.bold, color: bal > 0 ? Colors.green : Colors.grey)),
              );
            }).toList(),
          );
        }),
      ],
    );
  }

  Widget _buildManage() {
    final locCtrl = TextEditingController();
    final jpCtrl = TextEditingController();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Manage Locations & JP Names', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: TextField(controller: locCtrl, decoration: const InputDecoration(labelText: 'New Location'))),
            IconButton(icon: const Icon(Icons.add_circle, color: Colors.blue), onPressed: () {
              if (locCtrl.text.isNotEmpty) {
                setState(() => locations.add(locCtrl.text.trim()));
                _saveData();
                locCtrl.clear();
              }
            }),
          ],
        ),
        Wrap(spacing: 8, children: locations.map((l) => Chip(label: Text(l))).toList()),
        const Divider(height: 32),
        Row(
          children: [
            Expanded(child: TextField(controller: jpCtrl, decoration: const InputDecoration(labelText: 'New JP Name'))),
            IconButton(icon: const Icon(Icons.add_circle, color: Colors.orange), onPressed: () {
              if (jpCtrl.text.isNotEmpty) {
                setState(() => jpNames.add(jpCtrl.text.trim()));
                _saveData();
                jpCtrl.clear();
              }
            }),
          ],
        ),
        Wrap(spacing: 8, children: jpNames.map((j) => Chip(label: Text(j))).toList()),
      ],
    );
  }
}
