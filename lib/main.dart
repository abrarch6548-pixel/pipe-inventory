import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
  List<String> receivingLocations = ['Main Yard Receiving', 'Warehouse Gate 1', 'Bay 4 Discharge'];
  List<String> issueLocations = ['Yard 1', 'Yard 2', 'Warehouse A', 'Main Site Line'];
  List<String> jpNames = ['JP-Alpha', 'JP-Beta', 'JP-North', 'JP-Pipeline-01'];

  String _securityPin = '1234';

  final List<String> categories = [
    'Bare Pipe', 'Bare Bend', 'Painting Bend', 'Painting Pipe',
    '3LPP Pipe', '3LPP Bend', 'Spool', 'Cut Piece'
  ];

  final List<String> coatingOptions = [
    'Internal Coated', 'Without Internal Coating'
  ];

  String _stockSearchQuery = '';
  String _historySearchQuery = '';
  String _historyTypeFilter = 'ALL'; // ALL, RECEIVE, ISSUE, RETURN

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/pipe_inventory_master.json');
  }

  Future<void> _loadData() async {
    try {
      final file = await _getFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final data = jsonDecode(content);
        setState(() {
          transactions = List<Map<String, dynamic>>.from(data['transactions'] ?? []);
          if (data['receivingLocations'] != null) {
            receivingLocations = List<String>.from(data['receivingLocations']);
          }
          if (data['issueLocations'] != null) {
            issueLocations = List<String>.from(data['issueLocations']);
          }
          if (data['jpNames'] != null) {
            jpNames = List<String>.from(data['jpNames']);
          }
          if (data['securityPin'] != null) {
            _securityPin = data['securityPin'].toString();
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _saveData() async {
    try {
      final file = await _getFile();
      final payload = {
        'version': '2.7',
        'updatedAt': DateTime.now().toIso8601String(),
        'transactions': transactions,
        'receivingLocations': receivingLocations,
        'issueLocations': issueLocations,
        'jpNames': jpNames,
        'securityPin': _securityPin,
      };
      await file.writeAsString(jsonEncode(payload));
    } catch (_) {}
  }

  Future<bool> _authenticateAction(String actionTitle) async {
    final pinResult = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final pinCtrl = TextEditingController();
        String errorMsg = '';
        return StatefulBuilder(
          builder: (context, setDState) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.lock, color: Color(0xFF1E3A8A)),
                const SizedBox(width: 8),
                Expanded(child: Text('Security Lock - $actionTitle', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold))),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Please enter authorization PIN to proceed:'),
                const SizedBox(height: 12),
                TextField(
                  controller: pinCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Master PIN (Default: 1234)',
                    errorText: errorMsg.isNotEmpty ? errorMsg : null,
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.pin),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A8A)),
                onPressed: () {
                  if (pinCtrl.text.trim() == _securityPin.trim()) {
                    Navigator.pop(ctx, true);
                  } else {
                    setDState(() => errorMsg = 'Incorrect PIN!');
                  }
                },
                child: const Text('Authorize', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
      },
    );
    return pinResult ?? false;
  }

  // Stock Balance: (RECEIVE + RETURN) - ISSUE
  double _getStock(String size, String grade, String sch, String cat, String coating) {
    double total = 0;
    for (var t in transactions) {
      if ((t['pipeSize'] ?? '').toString().trim().toLowerCase() == size.trim().toLowerCase() &&
          (t['pipeGrade'] ?? '').toString().trim().toLowerCase() == grade.trim().toLowerCase() &&
          (t['pipeSch'] ?? '').toString().trim().toLowerCase() == sch.trim().toLowerCase() &&
          t['category'] == cat &&
          t['internalCoating'] == coating) {
        double qty = (t['quantity'] as num).toDouble();
        if (t['type'] == 'RECEIVE' || t['type'] == 'RETURN') total += qty;
        if (t['type'] == 'ISSUE') total -= qty;
      }
    }
    return total;
  }

  void _deleteTransactionById(String id) async {
    final authorized = await _authenticateAction('Delete Entry');
    if (!authorized) return;

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Entry Confirmation', style: TextStyle(color: Colors.red)),
        content: const Text('Are you sure you want to delete this entry? Stock balance will update automatically.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              setState(() {
                transactions.removeWhere((item) => item['id'] == id);
              });
              _saveData();
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Entry deleted & stock balance recalculated!')));
            },
            child: const Text('DELETE', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _editTransactionById(String id) async {
    final index = transactions.indexWhere((item) => item['id'] == id);
    if (index == -1) return;

    final authorized = await _authenticateAction('Edit Entry');
    if (!authorized) return;

    if (!mounted) return;
    final t = transactions[index];
    final sizeCtrl = TextEditingController(text: t['pipeSize'] ?? '');
    final gradeCtrl = TextEditingController(text: t['pipeGrade'] ?? '');
    final schCtrl = TextEditingController(text: t['pipeSch'] ?? '');
    final qtyCtrl = TextEditingController(text: t['quantity']?.toString() ?? '1');
    final entityCtrl = TextEditingController(text: t['entity'] ?? '');
    final remarksCtrl = TextEditingController(text: t['remarks'] ?? '');
    String cat = t['category'] ?? categories.first;
    String coat = t['internalCoating'] ?? coatingOptions.first;
    DateTime editDate = DateTime.tryParse(t['date'] ?? '') ?? DateTime.now();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDState) => AlertDialog(
          title: Text('Edit ${t['type']} Entry', style: const TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade200)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Date: ${DateFormat('yyyy-MM-dd').format(editDate)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.calendar_month, color: Color(0xFF1E3A8A)),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: editDate,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) setDState(() => editDate = picked);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                TextField(controller: sizeCtrl, decoration: const InputDecoration(labelText: 'Pipe Size')),
                TextField(controller: gradeCtrl, decoration: const InputDecoration(labelText: 'Pipe Grade')),
                TextField(controller: schCtrl, decoration: const InputDecoration(labelText: 'Pipe SCH')),
                DropdownButtonFormField<String>(
                  value: cat,
                  items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                  onChanged: (v) => setDState(() => cat = v!),
                  decoration: const InputDecoration(labelText: 'Category'),
                ),
                DropdownButtonFormField<String>(
                  value: coat,
                  items: coatingOptions.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                  onChanged: (v) => setDState(() => coat = v!),
                  decoration: const InputDecoration(labelText: 'Coating'),
                ),
                TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity')),
                TextField(controller: entityCtrl, decoration: InputDecoration(labelText: t['type'] == 'RECEIVE' ? 'Receiving Location' : (t['type'] == 'RETURN' ? 'Returned From' : 'Issued To'))),
                TextField(controller: remarksCtrl, decoration: const InputDecoration(labelText: 'Remarks / Reason')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                final newQty = double.tryParse(qtyCtrl.text) ?? 0;
                if (newQty <= 0) return;
                setState(() {
                  transactions[index]['date'] = DateFormat('yyyy-MM-dd').format(editDate);
                  transactions[index]['pipeSize'] = sizeCtrl.text.trim();
                  transactions[index]['pipeGrade'] = gradeCtrl.text.trim();
                  transactions[index]['pipeSch'] = schCtrl.text.trim();
                  transactions[index]['category'] = cat;
                  transactions[index]['internalCoating'] = coat;
                  transactions[index]['quantity'] = newQty;
                  transactions[index]['entity'] = entityCtrl.text.trim();
                  transactions[index]['remarks'] = remarksCtrl.text.trim();
                });
                _saveData();
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Entry updated & stock balance recalculated!')));
              },
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
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
          NavigationDestination(icon: Icon(Icons.assignment_return), label: 'Return'),
          NavigationDestination(icon: Icon(Icons.inventory_2), label: 'Stock'),
          NavigationDestination(icon: Icon(Icons.history), label: 'History'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Manage'),
        ],
      ),
    );
  }

  Widget _buildCurrentScreen() {
    if (_navIndex == 0) return _buildDashboard();
    if (_navIndex == 1) return _buildReceiving();
    if (_navIndex == 2) return _buildIssuing();
    if (_navIndex == 3) return _buildReturning();
    if (_navIndex == 4) return _buildStock();
    if (_navIndex == 5) return _buildHistory();
    return _buildManageAndBackup();
  }

  // --- DASHBOARD ---
  Widget _buildDashboard() {
    double received = 0;
    double issued = 0;
    double returned = 0;

    for (var t in transactions) {
      double q = (t['quantity'] as num).toDouble();
      if (t['type'] == 'RECEIVE') received += q;
      if (t['type'] == 'ISSUE') issued += q;
      if (t['type'] == 'RETURN') returned += q;
    }
    double balance = (received + returned) - issued;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Store Inventory KPI Overview', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Card(
          color: Colors.blue.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Current Total Available Stock (Rec + Ret - Iss)', style: TextStyle(color: Colors.grey)),
                Text('$balance Qty', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A))),
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
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Total Received', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      Text('$received', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: Card(
                color: Colors.teal.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Total Returned', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      Text('$returned', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal)),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: Card(
                color: Colors.orange.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Total Issued', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      Text('$issued', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Text('Recent Activities', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ...transactions.reversed.take(5).map((t) {
          IconData icon;
          Color color;
          if (t['type'] == 'RECEIVE') {
            icon = Icons.arrow_downward;
            color = Colors.green;
          } else if (t['type'] == 'RETURN') {
            icon = Icons.assignment_return;
            color = Colors.teal;
          } else {
            icon = Icons.arrow_upward;
            color = Colors.orange;
          }

          return Card(
            child: ListTile(
              leading: Icon(icon, color: color),
              title: Text('${t['category']} (${t['pipeSize']}) - ${t['internalCoating']}'),
              subtitle: Text('Grade: ${t['pipeGrade']} | SCH: ${t['pipeSch']}\nQty: ${t['quantity']} | Date: ${t['date']}'),
              trailing: Chip(
                label: Text(t['type'], style: const TextStyle(color: Colors.white, fontSize: 11)),
                backgroundColor: color,
              ),
            ),
          );
        }),
      ],
    );
  }

  // --- 1. RECEIVING MODULE ---
  Widget _buildReceiving() {
    final sizeCtrl = TextEditingController();
    final gradeCtrl = TextEditingController();
    final schCtrl = TextEditingController();
    final qtyCtrl = TextEditingController();
    final remarksCtrl = TextEditingController();
    String cat = categories.first;
    String coat = coatingOptions.first;
    String rLoc = receivingLocations.isNotEmpty ? receivingLocations.first : 'Yard Receiving';
    DateTime selectedDate = DateTime.now();

    return StatefulBuilder(
      builder: (context, setSub) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Stock Receiving Module', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade200)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Receiving Date (Auto-filled)', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      Text(DateFormat('yyyy-MM-dd').format(selectedDate), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A8A)),
                    icon: const Icon(Icons.calendar_month, color: Colors.white, size: 18),
                    label: const Text('Change Date', style: TextStyle(color: Colors.white)),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) setSub(() => selectedDate = picked);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(controller: sizeCtrl, decoration: const InputDecoration(labelText: 'Pipe Size (e.g., 24") *')),
            TextField(controller: gradeCtrl, decoration: const InputDecoration(labelText: 'Pipe Grade (e.g., X52, X65) *')),
            TextField(controller: schCtrl, decoration: const InputDecoration(labelText: 'Pipe SCH (e.g., 12.7, SCH 80) *')),
            DropdownButtonFormField<String>(
              value: cat,
              items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setSub(() => cat = v!),
              decoration: const InputDecoration(labelText: 'Category *'),
            ),
            DropdownButtonFormField<String>(
              value: coat,
              items: coatingOptions.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setSub(() => coat = v!),
              decoration: const InputDecoration(labelText: 'Internal Coating Type *'),
            ),
            TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity Received *')),
            DropdownButtonFormField<String>(
              value: rLoc,
              items: receivingLocations.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
              onChanged: (v) => setSub(() => rLoc = v!),
              decoration: const InputDecoration(labelText: 'Receiving Location *'),
            ),
            TextField(controller: remarksCtrl, decoration: const InputDecoration(labelText: 'Remarks / Heat Number')),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A8A), padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: () async {
                if (qtyCtrl.text.isEmpty || sizeCtrl.text.isEmpty || gradeCtrl.text.isEmpty || schCtrl.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all mandatory fields!')));
                  return;
                }

                final authorized = await _authenticateAction('Add Receiving Entry');
                if (!authorized) return;

                setState(() {
                  transactions.add({
                    'id': const Uuid().v4(),
                    'type': 'RECEIVE',
                    'pipeSize': sizeCtrl.text.trim(),
                    'pipeGrade': gradeCtrl.text.trim(),
                    'pipeSch': schCtrl.text.trim(),
                    'category': cat,
                    'internalCoating': coat,
                    'quantity': double.parse(qtyCtrl.text),
                    'entity': rLoc,
                    'date': DateFormat('yyyy-MM-dd').format(selectedDate),
                    'remarks': remarksCtrl.text.trim(),
                  });
                });
                _saveData();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Authorized: Pipes Received and Stock Incremented!')));
                  setState(() => _navIndex = 0);
                }
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text('AUTHORIZE & SUBMIT RECEIVING', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // --- 2. ISSUING MODULE ---
  Widget _buildIssuing() {
    final sizeCtrl = TextEditingController();
    final gradeCtrl = TextEditingController();
    final schCtrl = TextEditingController();
    final qtyCtrl = TextEditingController();
    final personCtrl = TextEditingController();
    String cat = categories.first;
    String coat = coatingOptions.first;
    String loc = issueLocations.isNotEmpty ? issueLocations.first : 'Yard 1';
    String jp = jpNames.isNotEmpty ? jpNames.first : 'JP-1';
    DateTime selectedDate = DateTime.now();

    return StatefulBuilder(
      builder: (context, setSub) {
        double currentStock = _getStock(sizeCtrl.text.trim(), gradeCtrl.text.trim(), schCtrl.text.trim(), cat, coat);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Stock Issuing Module', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange.shade200)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Issue Date (Auto-filled)', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      Text(DateFormat('yyyy-MM-dd').format(selectedDate), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEA580C)),
                    icon: const Icon(Icons.calendar_month, color: Colors.white, size: 18),
                    label: const Text('Change Date', style: TextStyle(color: Colors.white)),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) setSub(() => selectedDate = picked);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: currentStock > 0 ? Colors.green.shade50 : Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: currentStock > 0 ? Colors.green : Colors.red),
              ),
              child: Text(
                'Available Stock for this Spec: $currentStock Qty',
                style: TextStyle(fontWeight: FontWeight.bold, color: currentStock > 0 ? Colors.green.shade800 : Colors.red.shade800),
              ),
            ),
            const SizedBox(height: 8),
            TextField(controller: sizeCtrl, decoration: const InputDecoration(labelText: 'Pipe Size *'), onChanged: (_) => setSub(() {})),
            TextField(controller: gradeCtrl, decoration: const InputDecoration(labelText: 'Pipe Grade (e.g. X52) *'), onChanged: (_) => setSub(() {})),
            TextField(controller: schCtrl, decoration: const InputDecoration(labelText: 'Pipe SCH (e.g. 12.7) *'), onChanged: (_) => setSub(() {})),
            DropdownButtonFormField<String>(
              value: cat,
              items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setSub(() => cat = v!),
              decoration: const InputDecoration(labelText: 'Category *'),
            ),
            DropdownButtonFormField<String>(
              value: coat,
              items: coatingOptions.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setSub(() => coat = v!),
              decoration: const InputDecoration(labelText: 'Internal Coating *'),
            ),
            TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity to Issue *')),
            TextField(controller: personCtrl, decoration: const InputDecoration(labelText: 'Issued To / Person Name *')),
            DropdownButtonFormField<String>(
              value: loc,
              items: issueLocations.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
              onChanged: (v) => setSub(() => loc = v!),
              decoration: const InputDecoration(labelText: 'Destination Location *'),
            ),
            DropdownButtonFormField<String>(
              value: jp,
              items: jpNames.map((j) => DropdownMenuItem(value: j, child: Text(j))).toList(),
              onChanged: (v) => setSub(() => jp = v!),
              decoration: const InputDecoration(labelText: 'JP Name *'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEA580C), padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: () async {
                double req = double.tryParse(qtyCtrl.text) ?? 0;
                if (req <= 0) return;
                if (req > currentStock) {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Insufficient Stock Blocked', style: TextStyle(color: Colors.red)),
                      content: Text('Cannot issue $req pipes. Only $currentStock available for Size: ${sizeCtrl.text}, Grade: ${gradeCtrl.text}, SCH: ${schCtrl.text}.'),
                      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
                    ),
                  );
                  return;
                }

                final authorized = await _authenticateAction('Issue Pipe Stock');
                if (!authorized) return;

                setState(() {
                  transactions.add({
                    'id': const Uuid().v4(),
                    'type': 'ISSUE',
                    'pipeSize': sizeCtrl.text.trim(),
                    'pipeGrade': gradeCtrl.text.trim(),
                    'pipeSch': schCtrl.text.trim(),
                    'category': cat,
                    'internalCoating': coat,
                    'quantity': req,
                    'entity': personCtrl.text.trim(),
                    'location': loc,
                    'jpName': jp,
                    'date': DateFormat('yyyy-MM-dd').format(selectedDate),
                  });
                });
                _saveData();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Authorized: Pipes Issued and Deducted Successfully!')));
                  setState(() => _navIndex = 0);
                }
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text('AUTHORIZE & SUBMIT ISSUING', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // --- 3. RETURN MODULE (NEW: WAPSI STOCK MEIN JAMA) ---
  Widget _buildReturning() {
    final sizeCtrl = TextEditingController();
    final gradeCtrl = TextEditingController();
    final schCtrl = TextEditingController();
    final qtyCtrl = TextEditingController();
    final returnFromCtrl = TextEditingController();
    final remarksCtrl = TextEditingController();
    String cat = categories.first;
    String coat = coatingOptions.first;
    DateTime selectedDate = DateTime.now();

    return StatefulBuilder(
      builder: (context, setSub) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Row(
              children: [
                Icon(Icons.assignment_return, color: Colors.teal, size: 26),
                SizedBox(width: 8),
                Text('Stock Return (Pipe Wapsi)', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.teal)),
              ],
            ),
            const SizedBox(height: 6),
            const Text('Issued pipes jo site ya project se wapis aayein, wo yahan enter karein. Ye khud-ba-khud usi category aur spec ke stock mein add ho jayenge.', style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.teal.shade200)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Return Date (Auto-filled)', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      Text(DateFormat('yyyy-MM-dd').format(selectedDate), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                    icon: const Icon(Icons.calendar_month, color: Colors.white, size: 18),
                    label: const Text('Change Date', style: TextStyle(color: Colors.white)),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) setSub(() => selectedDate = picked);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(controller: sizeCtrl, decoration: const InputDecoration(labelText: 'Pipe Size (e.g. 24") *')),
            TextField(controller: gradeCtrl, decoration: const InputDecoration(labelText: 'Pipe Grade (e.g. X52) *')),
            TextField(controller: schCtrl, decoration: const InputDecoration(labelText: 'Pipe SCH (e.g. 12.7) *')),
            DropdownButtonFormField<String>(
              value: cat,
              items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setSub(() => cat = v!),
              decoration: const InputDecoration(labelText: 'Category *'),
            ),
            DropdownButtonFormField<String>(
              value: coat,
              items: coatingOptions.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setSub(() => coat = v!),
              decoration: const InputDecoration(labelText: 'Internal Coating *'),
            ),
            TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity Returned to Store *')),
            TextField(controller: returnFromCtrl, decoration: const InputDecoration(labelText: 'Returned From (Site / Person / Location) *')),
            TextField(controller: remarksCtrl, decoration: const InputDecoration(labelText: 'Reason for Return (Surplus / Cut Piece / Complete)')),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: () async {
                if (qtyCtrl.text.isEmpty || sizeCtrl.text.isEmpty || gradeCtrl.text.isEmpty || schCtrl.text.isEmpty || returnFromCtrl.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all mandatory fields!')));
                  return;
                }

                final authorized = await _authenticateAction('Add Return Entry');
                if (!authorized) return;

                setState(() {
                  transactions.add({
                    'id': const Uuid().v4(),
                    'type': 'RETURN',
                    'pipeSize': sizeCtrl.text.trim(),
                    'pipeGrade': gradeCtrl.text.trim(),
                    'pipeSch': schCtrl.text.trim(),
                    'category': cat,
                    'internalCoating': coat,
                    'quantity': double.parse(qtyCtrl.text),
                    'entity': returnFromCtrl.text.trim(),
                    'date': DateFormat('yyyy-MM-dd').format(selectedDate),
                    'remarks': remarksCtrl.text.trim(),
                  });
                });
                _saveData();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Success: Returned Pipes Added Back to Stock!')));
                  setState(() => _navIndex = 0);
                }
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text('AUTHORIZE & ADD RETURN TO STOCK', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // --- 4. DETAILED STOCK BREAKDOWN ---
  Widget _buildStock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Search by Grade (X52), SCH (12.7), Size (24")...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
            ),
            onChanged: (val) {
              setState(() {
                _stockSearchQuery = val.trim().toLowerCase();
              });
            },
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: categories.map((cat) {
              final specMap = <String, Map<String, String>>{};
              for (var t in transactions) {
                if (t['category'] == cat) {
                  final s = (t['pipeSize'] ?? '').toString().trim();
                  final g = (t['pipeGrade'] ?? '').toString().trim();
                  final sch = (t['pipeSch'] ?? '').toString().trim();
                  final key = '$s|$g|$sch';

                  if (_stockSearchQuery.isNotEmpty) {
                    final match = s.toLowerCase().contains(_stockSearchQuery) ||
                        g.toLowerCase().contains(_stockSearchQuery) ||
                        sch.toLowerCase().contains(_stockSearchQuery);
                    if (!match) continue;
                  }

                  if (!specMap.containsKey(key)) {
                    specMap[key] = {'size': s, 'grade': g, 'sch': sch};
                  }
                }
              }

              double catTotal = 0;
              for (var t in transactions) {
                if (t['category'] == cat) {
                  double q = (t['quantity'] as num).toDouble();
                  if (t['type'] == 'RECEIVE' || t['type'] == 'RETURN') catTotal += q;
                  if (t['type'] == 'ISSUE') catTotal -= q;
                }
              }

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                elevation: 2,
                child: ExpansionTile(
                  initiallyExpanded: specMap.isNotEmpty,
                  title: Text(cat, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E3A8A))),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: catTotal > 0 ? Colors.green.shade50 : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: catTotal > 0 ? Colors.green : Colors.grey),
                    ),
                    child: Text('Available: $catTotal', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: catTotal > 0 ? Colors.green.shade800 : Colors.grey.shade700)),
                  ),
                  children: specMap.isEmpty
                      ? [const Padding(padding: EdgeInsets.all(16.0), child: Text('No pipes recorded under this category.', style: TextStyle(color: Colors.grey)))]
                      : specMap.values.map((spec) {
                          final size = spec['size']!;
                          final grade = spec['grade']!;
                          final sch = spec['sch']!;

                          // Internal Coated
                          double cRec = 0, cRet = 0, cIss = 0;
                          for (var t in transactions) {
                            if (t['category'] == cat &&
                                (t['pipeSize'] ?? '').toString().trim().toLowerCase() == size.toLowerCase() &&
                                (t['pipeGrade'] ?? '').toString().trim().toLowerCase() == grade.toLowerCase() &&
                                (t['pipeSch'] ?? '').toString().trim().toLowerCase() == sch.toLowerCase() &&
                                t['internalCoating'] == 'Internal Coated') {
                              double q = (t['quantity'] as num).toDouble();
                              if (t['type'] == 'RECEIVE') cRec += q;
                              if (t['type'] == 'RETURN') cRet += q;
                              if (t['type'] == 'ISSUE') cIss += q;
                            }
                          }
                          double cBal = (cRec + cRet) - cIss;

                          // Without Internal Coating
                          double uRec = 0, uRet = 0, uIss = 0;
                          for (var t in transactions) {
                            if (t['category'] == cat &&
                                (t['pipeSize'] ?? '').toString().trim().toLowerCase() == size.toLowerCase() &&
                                (t['pipeGrade'] ?? '').toString().trim().toLowerCase() == grade.toLowerCase() &&
                                (t['pipeSch'] ?? '').toString().trim().toLowerCase() == sch.toLowerCase() &&
                                t['internalCoating'] == 'Without Internal Coating') {
                              double q = (t['quantity'] as num).toDouble();
                              if (t['type'] == 'RECEIVE') uRec += q;
                              if (t['type'] == 'RETURN') uRet += q;
                              if (t['type'] == 'ISSUE') uIss += q;
                            }
                          }
                          double uBal = (uRec + uRet) - uIss;

                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blueGrey.shade100)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(child: Text('Size: $size | Grade: $grade | SCH: $sch', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)))),
                                    Text('Net: ${cBal + uBal}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                                  ],
                                ),
                                const Divider(height: 14),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.circle, size: 8, color: Colors.teal),
                                        const SizedBox(width: 6),
                                        const Text('Internal Coated:', style: TextStyle(fontWeight: FontWeight.w600)),
                                        const SizedBox(width: 4),
                                        Text('(Rec: $cRec | Ret: $cRet | Iss: $cIss)', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                      ],
                                    ),
                                    Text('$cBal Qty', style: TextStyle(fontWeight: FontWeight.bold, color: cBal > 0 ? Colors.green.shade800 : Colors.grey.shade600)),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.circle, size: 8, color: Colors.amber),
                                        const SizedBox(width: 6),
                                        const Text('Without Internal Coating:', style: TextStyle(fontWeight: FontWeight.w600)),
                                        const SizedBox(width: 4),
                                        Text('(Rec: $uRec | Ret: $uRet | Iss: $uIss)', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                      ],
                                    ),
                                    Text('$uBal Qty', style: TextStyle(fontWeight: FontWeight.bold, color: uBal > 0 ? Colors.green.shade800 : Colors.grey.shade600)),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // --- 5. HISTORY & SEARCH ---
  Widget _buildHistory() {
    final filtered = transactions.where((t) {
      if (_historyTypeFilter == 'RECEIVE' && t['type'] != 'RECEIVE') return false;
      if (_historyTypeFilter == 'ISSUE' && t['type'] != 'ISSUE') return false;
      if (_historyTypeFilter == 'RETURN' && t['type'] != 'RETURN') return false;

      if (_historySearchQuery.isNotEmpty) {
        final q = _historySearchQuery;
        final locMatch = (t['entity'] ?? '').toString().toLowerCase().contains(q) ||
            (t['location'] ?? '').toString().toLowerCase().contains(q) ||
            (t['jpName'] ?? '').toString().toLowerCase().contains(q);
        final gradeMatch = (t['pipeGrade'] ?? '').toString().toLowerCase().contains(q);
        final sizeMatch = (t['pipeSize'] ?? '').toString().toLowerCase().contains(q);
        final schMatch = (t['pipeSch'] ?? '').toString().toLowerCase().contains(q);
        final catMatch = (t['category'] ?? '').toString().toLowerCase().contains(q);
        final dateMatch = (t['date'] ?? '').toString().toLowerCase().contains(q);
        final remarksMatch = (t['remarks'] ?? '').toString().toLowerCase().contains(q);

        return locMatch || gradeMatch || sizeMatch || schMatch || catMatch || dateMatch || remarksMatch;
      }
      return true;
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Search Location, Grade, Size, SCH, Date...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
              suffixIcon: _historySearchQuery.isNotEmpty
                  ? IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _historySearchQuery = ''))
                  : null,
            ),
            onChanged: (val) => setState(() => _historySearchQuery = val.trim().toLowerCase()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                FilterChip(
                  label: const Text('All (Both)'),
                  selected: _historyTypeFilter == 'ALL',
                  selectedColor: Colors.blue.shade100,
                  onSelected: (_) => setState(() => _historyTypeFilter = 'ALL'),
                ),
                const SizedBox(width: 6),
                FilterChip(
                  label: const Text('Receiving'),
                  selected: _historyTypeFilter == 'RECEIVE',
                  selectedColor: Colors.green.shade100,
                  onSelected: (_) => setState(() => _historyTypeFilter = 'RECEIVE'),
                ),
                const SizedBox(width: 6),
                FilterChip(
                  label: const Text('Issuing'),
                  selected: _historyTypeFilter == 'ISSUE',
                  selectedColor: Colors.orange.shade100,
                  onSelected: (_) => setState(() => _historyTypeFilter = 'ISSUE'),
                ),
                const SizedBox(width: 6),
                FilterChip(
                  label: const Text('Returns (Wapsi)'),
                  selected: _historyTypeFilter == 'RETURN',
                  selectedColor: Colors.teal.shade100,
                  onSelected: (_) => setState(() => _historyTypeFilter = 'RETURN'),
                ),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          color: Colors.blue.shade50,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Showing ${filtered.length} of ${transactions.length} entries', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const Text('PIN Protected', style: TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('No matching records found.'))
              : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final t = filtered[index];
                    final tId = t['id'];

                    IconData icon;
                    Color color;
                    if (t['type'] == 'RECEIVE') {
                      icon = Icons.download;
                      color = Colors.green;
                    } else if (t['type'] == 'RETURN') {
                      icon = Icons.assignment_return;
                      color = Colors.teal;
                    } else {
                      icon = Icons.upload;
                      color = Colors.orange;
                    }

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: color.withOpacity(0.15),
                          child: Icon(icon, color: color),
                        ),
                        title: Text('${t['category']} (${t['pipeSize']}) - ${t['internalCoating']}'),
                        subtitle: Text('Grade: ${t['pipeGrade']} | SCH: ${t['pipeSch']}\nQty: ${t['quantity']} | Date: ${t['date']}\nLoc: ${t['entity'] ?? t['location']}${t['jpName'] != null ? ' | JP: ${t['jpName']}' : ''}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(icon: const Icon(Icons.edit, color: Colors.blue), tooltip: 'Edit', onPressed: () => _editTransactionById(tId)),
                            IconButton(icon: const Icon(Icons.delete, color: Colors.red), tooltip: 'Delete', onPressed: () => _deleteTransactionById(tId)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // --- 6. MANAGE & BACKUP ---
  Widget _buildManageAndBackup() {
    final rLocCtrl = TextEditingController();
    final iLocCtrl = TextEditingController();
    final jpCtrl = TextEditingController();
    final restoreTextCtrl = TextEditingController();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Security & Access Protection', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Card(
          color: Colors.amber.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.lock, color: Color(0xFF1E3A8A), size: 28),
                    SizedBox(width: 8),
                    Text('Master PIN Authorization', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
                const SizedBox(height: 6),
                const Text('New Entry, Return, Edit, aur Delete sab security lock se protected hain.'),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Current PIN:  $_securityPin', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A8A)),
                      icon: const Icon(Icons.pin, color: Colors.white, size: 16),
                      label: const Text('Change PIN', style: TextStyle(color: Colors.white)),
                      onPressed: () {
                        final oldPinCtrl = TextEditingController();
                        final newPinCtrl = TextEditingController();
                        String errorTxt = '';

                        showDialog(
                          context: context,
                          builder: (ctx) => StatefulBuilder(
                            builder: (context, setDState) => AlertDialog(
                              title: const Text('Change Security PIN'),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextField(controller: oldPinCtrl, obscureText: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Current PIN')),
                                  const SizedBox(height: 8),
                                  TextField(controller: newPinCtrl, obscureText: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'New PIN')),
                                  if (errorTxt.isNotEmpty) ...[const SizedBox(height: 8), Text(errorTxt, style: const TextStyle(color: Colors.red))],
                                ],
                              ),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                                ElevatedButton(
                                  onPressed: () {
                                    if (oldPinCtrl.text.trim() != _securityPin.trim()) {
                                      setDState(() => errorTxt = 'Current PIN is incorrect!');
                                      return;
                                    }
                                    if (newPinCtrl.text.trim().isEmpty) {
                                      setDState(() => errorTxt = 'Enter valid new PIN!');
                                      return;
                                    }
                                    setState(() => _securityPin = newPinCtrl.text.trim());
                                    _saveData();
                                    Navigator.pop(ctx);
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Master Security PIN Updated!')));
                                  },
                                  child: const Text('Update PIN'),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 28),
        const Text('Backup & Data Protection', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Card(
          color: Colors.blue.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Export Complete Data (Backup)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const Text('Click kar ke sara data copy aur file me save karein.'),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A8A)),
                  icon: const Icon(Icons.download, color: Colors.white),
                  label: const Text('CREATE BACKUP (EXPORT)', style: TextStyle(color: Colors.white)),
                  onPressed: () async {
                    final payload = {
                      'timestamp': DateTime.now().toIso8601String(),
                      'transactions': transactions,
                      'receivingLocations': receivingLocations,
                      'issueLocations': issueLocations,
                      'jpNames': jpNames,
                      'securityPin': _securityPin,
                    };
                    final jsonStr = jsonEncode(payload);
                    Clipboard.setData(ClipboardData(text: jsonStr));

                    final dir = await getApplicationDocumentsDirectory();
                    final bFile = File('${dir.path}/pipe_backup_${DateTime.now().millisecondsSinceEpoch}.json');
                    await bFile.writeAsString(jsonStr);

                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Backup Created Successfully!'),
                        content: Text('Backup saved to: ${bFile.path}\n\nData clipboard mein bhi copy ho gaya hai! WhatsApp ya Drive par save kar lein.'),
                        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          color: Colors.green.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Restore Data from Backup', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const Text('Purana backup text paste kar ke data wapis laein.'),
                const SizedBox(height: 8),
                TextField(controller: restoreTextCtrl, maxLines: 2, decoration: const InputDecoration(hintText: 'Paste backup JSON text here...', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade800),
                  icon: const Icon(Icons.restore, color: Colors.white),
                  label: const Text('RESTORE DATA NOW', style: TextStyle(color: Colors.white)),
                  onPressed: () async {
                    if (restoreTextCtrl.text.isEmpty) return;
                    final authorized = await _authenticateAction('Restore Database');
                    if (!authorized) return;

                    try {
                      final data = jsonDecode(restoreTextCtrl.text.trim());
                      setState(() {
                        if (data['transactions'] != null) transactions = List<Map<String, dynamic>>.from(data['transactions']);
                        if (data['receivingLocations'] != null) receivingLocations = List<String>.from(data['receivingLocations']);
                        if (data['issueLocations'] != null) issueLocations = List<String>.from(data['issueLocations']);
                        if (data['jpNames'] != null) jpNames = List<String>.from(data['jpNames']);
                        if (data['securityPin'] != null) _securityPin = data['securityPin'].toString();
                      });
                      _saveData();
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Data Restored Successfully!')));
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid Backup Data!')));
                    }
                  },
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 28),
        const Text('Receiving Locations Management', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Row(
          children: [
            Expanded(child: TextField(controller: rLocCtrl, decoration: const InputDecoration(labelText: 'New Receiving Location'))),
            IconButton(
              icon: const Icon(Icons.add_circle, color: Colors.blue, size: 30),
              onPressed: () {
                if (rLocCtrl.text.isNotEmpty) {
                  setState(() => receivingLocations.add(rLocCtrl.text.trim()));
                  _saveData();
                  rLocCtrl.clear();
                }
              },
            ),
          ],
        ),
        Wrap(spacing: 8, children: receivingLocations.map((l) => Chip(
          label: Text(l),
          onDeleted: () {
            setState(() => receivingLocations.remove(l));
            _saveData();
          },
        )).toList()),
        const Divider(height: 28),
        const Text('Issue Destination Locations', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Row(
          children: [
            Expanded(child: TextField(controller: iLocCtrl, decoration: const InputDecoration(labelText: 'New Issue Location'))),
            IconButton(
              icon: const Icon(Icons.add_circle, color: Colors.green, size: 30),
              onPressed: () {
                if (iLocCtrl.text.isNotEmpty) {
                  setState(() => issueLocations.add(iLocCtrl.text.trim()));
                  _saveData();
                  iLocCtrl.clear();
                }
              },
            ),
          ],
        ),
        Wrap(spacing: 8, children: issueLocations.map((l) => Chip(
          label: Text(l),
          onDeleted: () {
            setState(() => issueLocations.remove(l));
            _saveData();
          },
        )).toList()),
        const Divider(height: 28),
        const Text('JP Names (Joint Proposals)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Row(
          children: [
            Expanded(child: TextField(controller: jpCtrl, decoration: const InputDecoration(labelText: 'New JP Name'))),
            IconButton(
              icon: const Icon(Icons.add_circle, color: Colors.orange, size: 30),
              onPressed: () {
                if (jpCtrl.text.isNotEmpty) {
                  setState(() => jpNames.add(jpCtrl.text.trim()));
                  _saveData();
                  jpCtrl.clear();
                }
              },
            ),
          ],
        ),
        Wrap(spacing: 8, children: jpNames.map((j) => Chip(
          label: Text(j),
          onDeleted: () {
            setState(() => jpNames.remove(j));
            _saveData();
          },
        )).toList()),
      ],
    );
  }
}
