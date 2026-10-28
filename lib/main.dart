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
        });
      }
    } catch (_) {}
  }

  Future<void> _saveData() async {
    try {
      final file = await _getFile();
      final payload = {
        'version': '2.0',
        'updatedAt': DateTime.now().toIso8601String(),
        'transactions': transactions,
        'receivingLocations': receivingLocations,
        'issueLocations': issueLocations,
        'jpNames': jpNames,
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

  void _deleteTransaction(int index) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Entry Confirmation', style: TextStyle(color: Colors.red)),
        content: const Text('Are you sure you want to delete this inventory entry? Stock balance will update automatically.'),
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

  void _editTransaction(int index) {
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
          NavigationDestination(icon: Icon(Icons.settings), label: 'Manage & Backup'),
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
            subtitle: Text('Qty: ${t['quantity']} | Date: ${t['date']}\nLoc: ${t['entity'] ?? t['location']}'),
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
            TextField(controller: gradeCtrl, decoration: const InputDecoration(labelText: 'Pipe Grade (e.g., X65) *')),
            TextField(controller: schCtrl, decoration: const InputDecoration(labelText: 'Pipe SCH (e.g., SCH 80) *')),
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
              onPressed: () {
                if (qtyCtrl.text.isEmpty || sizeCtrl.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill mandatory fields!')));
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
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pipes Received and Stock Incremented!')));
                setState(() => _navIndex = 0);
              },
              child: const Text('SUBMIT RECEIVING TRANSACTION', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                'Available Stock for Configuration: $currentStock Qty',
                style: TextStyle(fontWeight: FontWeight.bold, color: currentStock > 0 ? Colors.green.shade800 : Colors.red.shade800),
              ),
            ),
            const SizedBox(height: 8),
            TextField(controller: serialCtrl, decoration: const InputDecoration(labelText: 'Serial Number / Pipe ID')),
            TextField(controller: sizeCtrl, decoration: const InputDecoration(labelText: 'Pipe Size *'), onChanged: (_) => setSub(() {})),
            TextField(controller: gradeCtrl, decoration: const InputDecoration(labelText: 'Pipe Grade *'), onChanged: (_) => setSub(() {})),
            TextField(controller: schCtrl, decoration: const InputDecoration(labelText: 'Pipe SCH *'), onChanged: (_) => setSub(() {})),
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
              onPressed: () {
                double req = double.tryParse(qtyCtrl.text) ?? 0;
                if (req <= 0) return;
                if (req > currentStock) {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Insufficient Stock Blocked', style: TextStyle(color: Colors.red)),
                      content: Text('Cannot issue $req pipes. Only $currentStock available in store.'),
                      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
                    ),
                  );
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
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pipes Issued and Deducted Successfully!')));
                setState(() => _navIndex = 0);
              },
              child: const Text('SUBMIT ISSUING TRANSACTION', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
        const Text('Current Live Stock Balances', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        ...categories.map((c) {
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ExpansionTile(
              title: Text(c, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A))),
              children: coatingOptions.map((coat) {
                double bal = 0;
                double rec = 0;
                double iss = 0;
                for (var t in transactions) {
                  if (t['category'] == c && t['internalCoating'] == coat) {
                    double q = (t['quantity'] as num).toDouble();
                    if (t['type'] == 'RECEIVE') rec += q;
                    if (t['type'] == 'ISSUE') iss += q;
                  }
                }
                bal = rec - iss;
                return ListTile(
                  title: Text(coat),
                  subtitle: Text('Total Rec: $rec | Total Iss: $iss'),
                  trailing: Text(
                    '$bal Qty',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: bal > 0 ? Colors.green.shade800 : Colors.grey,
                    ),
                  ),
                );
              }).toList(),
            ),
          );
        }),
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
              const Icon(Icons.info_outline, color: Color(0xFF1E3A8A)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Total Entries Recorded: ${transactions.length}\nAap kisi bhi ghalat entry ko edit ya delete kar sakte hain.',
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
                        title: Text('${t['category']} (${t['pipeSize']} / ${t['pipeGrade']})'),
                        subtitle: Text('Qty: ${t['quantity']} | Date: ${t['date']}\nLoc: ${t['entity'] ?? t['location']}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              tooltip: 'Edit Entry',
                              onPressed: () => _editTransaction(index),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              tooltip: 'Delete Entry',
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
        const Text('Backup & Data Protection', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
                  onPressed: () {
                    if (restoreTextCtrl.text.isEmpty) return;
                    try {
                      final data = jsonDecode(restoreTextCtrl.text.trim());
                      setState(() {
                        if (data['transactions'] != null) transactions = List<Map<String, dynamic>>.from(data['transactions']);
                        if (data['receivingLocations'] != null) receivingLocations = List<String>.from(data['receivingLocations']);
                        if (data['issueLocations'] != null) issueLocations = List<String>.from(data['issueLocations']);
                        if (data['jpNames'] != null) jpNames = List<String>.from(data['jpNames']);
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
        const Divider(height: 32),
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
        const Divider(height: 32),
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
        const Divider(height: 32),
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
