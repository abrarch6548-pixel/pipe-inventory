import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:local_auth/local_auth.dart';
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

  // Security Lock
  String _securityPin = '1234';
  final LocalAuthentication _auth = LocalAuthentication();

  final List<String> categories = [
    'Bare Pipe', 'Bare Bend', 'Painting Bend', 'Painting Pipe',
    '3LPP Pipe', '3LPP Bend', 'Spool', 'Cut Piece'
  ];

  final List<String> coatingOptions = [
    'Internal Coated', 'Without Internal Coating'
  ];

  String _stockSearchQuery = '';

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
        'version': '2.2',
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

  // --- BIOMETRIC FINGERPRINT & PASSWORD VERIFICATION ---
  Future<bool> _authenticateAction(String actionTitle) async {
    // 1. Try Fingerprint Biometrics
    try {
      final bool canCheck = await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
      if (canCheck) {
        final bool didAuth = await _auth.authenticate(
          localizedReason: 'Please authenticate with Fingerprint to $actionTitle',
          options: const AuthenticationOptions(
            stickyAuth: true,
            biometricOnly: false,
          ),
        );
        if (didAuth) return true;
      }
    } catch (e) {
      debugPrint("Biometric bypass or unsupported: $e");
    }

    // 2. Fallback to Master Password / PIN Dialog
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
                Expanded(child: Text('Security Lock - $actionTitle', style: const TextStyle(fontSize: 16))),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Please enter authorization Password / PIN to proceed:'),
                const SizedBox(height: 12),
                TextField(
                  controller: pinCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Master PIN / Password',
                    errorText: errorMsg.isNotEmpty ? errorMsg : null,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A8A)),
                onPressed: () {
                  if (pinCtrl.text.trim() == _securityPin.trim()) {
                    Navigator.pop(ctx, true);
                  } else {
                    setDState(() {
                      errorMsg = 'Incorrect Password / PIN!';
                    });
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

  double _getStock(String size, String grade, String sch, String cat, String coating) {
    double total = 0;
    for (var t in transactions) {
      if ((t['pipeSize'] ?? '').toString().trim().toLowerCase() == size.trim().toLowerCase() &&
          (t['pipeGrade'] ?? '').toString().trim().toLowerCase() == grade.trim().toLowerCase() &&
          (t['pipeSch'] ?? '').toString().trim().toLowerCase() == sch.trim().toLowerCase() &&
          t['category'] == cat &&
          t['internalCoating'] == coating) {
        double qty = (t['quantity'] as num).toDouble();
        if (t['type'] == 'RECEIVE') total += qty;
        if (t['type'] == 'ISSUE') total -= qty;
      }
    }
    return total;
  }

  void _deleteTransaction(int index) async {
    final authorized = await _authenticateAction('Delete Entry');
    if (!authorized) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Action cancelled or unauthorized!')));
      }
      return;
    }

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Entry Confirmation', style: TextStyle(color: Colors.red)),
        content: const Text('Are you sure you want to permanently delete this inventory entry? Stock balance will update automatically.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              setState(() {
                transactions.removeAt(index);
              });
              _saveData();
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Entry deleted and stock balance updated!')),
              );
            },
            child: const Text('DELETE', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _editTransaction(int index) async {
    final authorized = await _authenticateAction('Edit Entry');
    if (!authorized) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Action cancelled or unauthorized!')));
      }
      return;
    }

    if (!mounted) return;
    final t = transactions[index];
    final serialCtrl = TextEditingController(text: t['serial'] ?? '');
    final sizeCtrl = TextEditingController(text: t['pipeSize'] ?? '');
    final gradeCtrl = TextEditingController(text: t['pipeGrade'] ?? '');
    final schCtrl = TextEditingController(text: t['pipeSch'] ?? '');
    final qtyCtrl = TextEditingController(text: t['quantity']?.toString() ?? '1');
    final entityCtrl = TextEditingController(text: t['entity'] ?? '');
    final remarksCtrl = TextEditingController(text: t['remarks'] ?? '');
    String cat = t['category'] ?? categories.first;
    String coat = t['internalCoating'] ?? coatingOptions.first;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDState) => AlertDialog(
          title: Text('Edit ${t['type']} Entry', style: const TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: serialCtrl, decoration: const InputDecoration(labelText: 'Serial No / ID')),
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
                TextField(controller: entityCtrl, decoration: InputDecoration(labelText: t['type'] == 'RECEIVE' ? 'Receiving Location' : 'Issued To')),
                TextField(controller: remarksCtrl, decoration: const InputDecoration(labelText: 'Remarks')),
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
                  transactions[index]['serial'] = serialCtrl.text.trim();
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
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Entry successfully updated & stock recalculated!')),
                );
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
          NavigationDestination(icon: Icon(Icons.inventory_2), label: 'Stock'),
          NavigationDestination(icon: Icon(Icons.history), label: 'History & Edit'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Manage & Security'),
        ],
      ),
    );
  }

  Widget _buildCurrentScreen() {
    if (_navIndex == 0) return _buildDashboard();
    if (_navIndex == 1) return _buildReceiving();
    if (_navIndex == 2) return _buildIssuing();
    if (_navIndex == 3) return _buildStock();
    if (_navIndex == 4) return _buildHistory();
    return _buildManageAndBackup();
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
        const Text('Store Inventory KPI Overview', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Card(
          color: Colors.blue.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Current Total Pipe Stock', style: TextStyle(color: Colors.grey)),
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
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Total Received', style: TextStyle(color: Colors.grey)),
                      Text('$received', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.green)),
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
                      Text('$issued', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.orange)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Text('Quick Recent Actions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ...transactions.reversed.take(4).map((t) => Card(
          child: ListTile(
            leading: Icon(
              t['type'] == 'RECEIVE' ? Icons.arrow_downward : Icons.arrow_upward,
              color: t['type'] == 'RECEIVE' ? Colors.green : Colors.orange,
            ),
            title: Text('${t['category']} (${t['pipeSize']}) - ${t['internalCoating']}'),
            subtitle: Text('Grade: ${t['pipeGrade']} | SCH: ${t['pipeSch']}\nQty: ${t['quantity']} | Date: ${t['date']}'),
            trailing: Chip(
              label: Text(t['type'], style: const TextStyle(color: Colors.white, fontSize: 11)),
              backgroundColor: t['type'] == 'RECEIVE' ? Colors.green : Colors.orange,
            ),
          ),
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
    String rLoc = receivingLocations.isNotEmpty ? receivingLocations.first : 'Yard Receiving';

    return StatefulBuilder(
      builder: (context, setSub) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Stock Receiving Module', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(controller: serialCtrl, decoration: const InputDecoration(labelText: 'Serial Number / Pipe ID *')),
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

                // Security Authorization Prompt
                final authorized = await _authenticateAction('Add Receiving Entry');
                if (!authorized) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Action cancelled or unauthorized!')));
                  }
                  return;
                }

                setState(() {
                  transactions.add({
                    'id': const Uuid().v4(),
                    'type': 'RECEIVE',
                    'serial': serialCtrl.text.trim(),
                    'pipeSize': sizeCtrl.text.trim(),
                    'pipeGrade': gradeCtrl.text.trim(),
                    'pipeSch': schCtrl.text.trim(),
                    'category': cat,
                    'internalCoating': coat,
                    'quantity': double.parse(qtyCtrl.text),
                    'entity': rLoc,
                    'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
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
                  Icon(Icons.fingerprint, color: Colors.white),
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

  Widget _buildIssuing() {
    final serialCtrl = TextEditingController();
    final sizeCtrl = TextEditingController();
    final gradeCtrl = TextEditingController();
    final schCtrl = TextEditingController();
    final qtyCtrl = TextEditingController();
    final personCtrl = TextEditingController();
    String cat = categories.first;
    String coat = coatingOptions.first;
    String loc = issueLocations.isNotEmpty ? issueLocations.first : 'Yard 1';
    String jp = jpNames.isNotEmpty ? jpNames.first : 'JP-1';

    return StatefulBuilder(
      builder: (context, setSub) {
        double currentStock = _getStock(sizeCtrl.text.trim(), gradeCtrl.text.trim(), schCtrl.text.trim(), cat, coat);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Stock Issuing Module', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
            TextField(controller: serialCtrl, decoration: const InputDecoration(labelText: 'Serial Number / Pipe ID')),
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

                // Security Authorization Prompt
                final authorized = await _authenticateAction('Issue Pipe Stock');
                if (!authorized) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Action cancelled or unauthorized!')));
                  }
                  return;
                }

                setState(() {
                  transactions.add({
                    'id': const Uuid().v4(),
                    'type': 'ISSUE',
                    'serial': serialCtrl.text.trim(),
                    'pipeSize': sizeCtrl.text.trim(),
                    'pipeGrade': gradeCtrl.text.trim(),
                    'pipeSch': schCtrl.text.trim(),
                    'category': cat,
                    'internalCoating': coat,
                    'quantity': req,
                    'entity': personCtrl.text.trim(),
                    'location': loc,
                    'jpName': jp,
                    'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
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
                  Icon(Icons.fingerprint, color: Colors.white),
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

  // --- DETAILED STOCK BREAKDOWN BY SIZE, GRADE, SCH & COATING ---
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
                  if (t['type'] == 'RECEIVE') catTotal += q;
                  if (t['type'] == 'ISSUE') catTotal -= q;
                }
              }

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                elevation: 2,
                child: ExpansionTile(
                  initiallyExpanded: specMap.isNotEmpty,
                  title: Text(
                    cat,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E3A8A)),
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: catTotal > 0 ? Colors.green.shade50 : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: catTotal > 0 ? Colors.green : Colors.grey),
                    ),
                    child: Text(
                      'Total: $catTotal',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: catTotal > 0 ? Colors.green.shade800 : Colors.grey.shade700,
                      ),
                    ),
                  ),
                  children: [
                    if (specMap.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text('No pipes recorded under this category.', style: TextStyle(color: Colors.grey)),
                      )
                    else
                      ...specMap.values.map((spec) {
                        final size = spec['size']!;
                        final grade = spec['grade']!;
                        final sch = spec['sch']!;

                        double coatedRec = 0;
                        double coatedIss = 0;
                        for (var t in transactions) {
                          if (t['category'] == cat &&
                              (t['pipeSize'] ?? '').toString().trim().toLowerCase() == size.toLowerCase() &&
                              (t['pipeGrade'] ?? '').toString().trim().toLowerCase() == grade.toLowerCase() &&
                              (t['pipeSch'] ?? '').toString().trim().toLowerCase() == sch.toLowerCase() &&
                              t['internalCoating'] == 'Internal Coated') {
                            double q = (t['quantity'] as num).toDouble();
                            if (t['type'] == 'RECEIVE') coatedRec += q;
                            if (t['type'] == 'ISSUE') coatedIss += q;
                          }
                        }
                        double coatedBal = coatedRec - coatedIss;

                        double unCoatedRec = 0;
                        double unCoatedIss = 0;
                        for (var t in transactions) {
                          if (t['category'] == cat &&
                              (t['pipeSize'] ?? '').toString().trim().toLowerCase() == size.toLowerCase() &&
                              (t['pipeGrade'] ?? '').toString().trim().toLowerCase() == grade.toLowerCase() &&
                              (t['pipeSch'] ?? '').toString().trim().toLowerCase() == sch.toLowerCase() &&
                              t['internalCoating'] == 'Without Internal Coating') {
                            double q = (t['quantity'] as num).toDouble();
                            if (t['type'] == 'RECEIVE') unCoatedRec += q;
                            if (t['type'] == 'ISSUE') unCoatedIss += q;
                          }
                        }
                        double unCoatedBal = unCoatedRec - unCoatedIss;

                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blueGrey.shade100),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Size: $size | Grade: $grade | SCH: $sch',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)),
                                    ),
                                  ),
                                  Text(
                                    'Net: ${coatedBal + unCoatedBal}',
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent),
                                  ),
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
                                      Text('(Rec: $coatedRec | Iss: $coatedIss)', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                    ],
                                  ),
                                  Text(
                                    '$coatedBal Qty',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: coatedBal > 0 ? Colors.green.shade800 : Colors.grey.shade600,
                                    ),
                                  ),
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
                                      Text('(Rec: $unCoatedRec | Iss: $unCoatedIss)', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                    ],
                                  ),
                                  Text(
                                    '$unCoatedBal Qty',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: unCoatedBal > 0 ? Colors.green.shade800 : Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildHistory() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.blue.shade50,
          child: Row(
            children: [
              const Icon(Icons.security, color: Color(0xFF1E3A8A)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Total Entries: ${transactions.length}\nEditing aur Deletion Security Lock se protected hain.',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: transactions.isEmpty
              ? const Center(child: Text('No transactions yet.'))
              : ListView.builder(
                  itemCount: transactions.length,
                  itemBuilder: (context, index) {
                    final t = transactions[index];
                    final isReceive = t['type'] == 'RECEIVE';
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isReceive ? Colors.green.shade100 : Colors.orange.shade100,
                          child: Icon(isReceive ? Icons.download : Icons.upload, color: isReceive ? Colors.green : Colors.orange),
                        ),
                        title: Text('${t['category']} (${t['pipeSize']}) - ${t['internalCoating']}'),
                        subtitle: Text('Grade: ${t['pipeGrade']} | SCH: ${t['pipeSch']}\nQty: ${t['quantity']} | Date: ${t['date']}\nLoc: ${t['entity'] ?? t['location']}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              tooltip: 'Edit Entry (Locked)',
                              onPressed: () => _editTransaction(index),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              tooltip: 'Delete Entry (Locked)',
                              onPressed: () => _deleteTransaction(index),
                            ),
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

  Widget _buildManageAndBackup() {
    final rLocCtrl = TextEditingController();
    final iLocCtrl = TextEditingController();
    final jpCtrl = TextEditingController();
    final restoreTextCtrl = TextEditingController();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // --- MASTER SECURITY SETTINGS ---
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
                    Icon(Icons.fingerprint, color: Color(0xFF1E3A8A), size: 28),
                    SizedBox(width: 8),
                    Text('Fingerprint & Password Authorization', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
                const SizedBox(height: 6),
                const Text('New Entry, Edit, aur Delete sab security lock se protected hain.'),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Current Master PIN:  $_securityPin', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
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
                                  TextField(
                                    controller: oldPinCtrl,
                                    obscureText: true,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(labelText: 'Current PIN'),
                                  ),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: newPinCtrl,
                                    obscureText: true,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(labelText: 'New PIN (e.g. 4 digits)'),
                                  ),
                                  if (errorTxt.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(errorTxt, style: const TextStyle(color: Colors.red)),
                                  ],
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
                                    setState(() {
                                      _securityPin = newPinCtrl.text.trim();
                                    });
                                    _saveData();
                                    Navigator.pop(ctx);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Master Security PIN Updated Successfully!')),
                                    );
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
                const Text('Aap is button par click kar ke sara data copy ya file me save kar sakte hain.'),
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
                        content: Text('Backup saved to: ${bFile.path}\n\nData clipboard mein bhi copy ho gaya hai! Aap isay WhatsApp ya Drive par paste kar ke mehfooz rakh sakte hain.'),
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
                const Text('Agar app dobara install karein to purana backup data yahan paste kar ke restore karein.'),
                const SizedBox(height: 8),
                TextField(
                  controller: restoreTextCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(hintText: 'Paste backup JSON text here...', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade800),
                  icon: const Icon(Icons.restore, color: Colors.white),
                  label: const Text('RESTORE DATA NOW', style: TextStyle(color: Colors.white)),
                  onPressed: () async {
                    if (restoreTextCtrl.text.isEmpty) return;
                    final authorized = await _authenticateAction('Restore Database');
                    if (!authorized) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Action cancelled or unauthorized!')));
                      return;
                    }
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
