import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'second_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Club Logistics',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.pink),
        scaffoldBackgroundColor: const Color(0xFFFFF7F9),
      ),
      home: const MyHomePage(title: 'Club Logistics'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  // Collection dalam Firestore
  final CollectionReference<Map<String, dynamic>> _items =
  FirebaseFirestore.instance.collection('logistics');

  // Penapis semasa: pending, all, return, buy
  String _filter = 'pending';

  // ---------- Fungsi bantuan ----------

  String _formatDate(Timestamp ts) {
    final d = ts.toDate();
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  bool _isOverdue(Timestamp? ts, bool done) {
    if (ts == null || done) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return ts.toDate().isBefore(today);
  }

  Future<void> _confirmDelete(DocumentReference ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Padam item?'),
        content: const Text('Item ini akan dipadam terus.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Padam'),
          ),
        ],
      ),
    );
    if (ok == true) await ref.delete();
  }

  // ---------- Widget kecil ----------

  // Kotak statistik dalam header
  Widget _statBox(IconData icon, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.pink.shade50,
              child: Icon(icon, color: Colors.pink),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    label,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Label kecil berwarna (contoh: "Beli", "Lewat", "RM 10.00")
  Widget _pill(String text, Color bg, Color fg, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(fontSize: 12, color: fg, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String value, String label) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: _filter == value,
        selectedColor: Colors.pink.shade100,
        onSelected: (_) => setState(() => _filter = value),
      ),
    );
  }

  // Satu kad item
  Widget _buildItemCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final done = data['done'] == true;
    final isBuy = data['type'] == 'buy';
    final party = (data['party'] ?? '') as String;
    final cost = (data['cost'] as num?)?.toDouble();
    final due = data['dueDate'] as Timestamp?;
    final overdue = _isOverdue(due, done);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 1,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Checkbox settle
            Checkbox(
              value: done,
              activeColor: Colors.pink,
              onChanged: (v) => doc.reference.update({'done': v}),
            ),
            // Maklumat item
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data['item'] ?? '',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: done ? Colors.grey : Colors.black87,
                        decoration: done ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isBuy ? 'Beli di: $party' : 'Pulang kepada: $party',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        isBuy
                            ? _pill('Beli', Colors.blue.shade50,
                            Colors.blue.shade700,
                            icon: Icons.shopping_cart_outlined)
                            : _pill('Pulang', Colors.orange.shade50,
                            Colors.orange.shade800,
                            icon: Icons.assignment_return_outlined),
                        if (cost != null)
                          _pill('RM ${cost.toStringAsFixed(2)}',
                              Colors.green.shade50, Colors.green.shade700,
                              icon: Icons.payments_outlined),
                        if (due != null)
                          _pill(
                            _formatDate(due),
                            overdue ? Colors.red.shade50 : Colors.grey.shade100,
                            overdue ? Colors.red.shade700 : Colors.grey.shade700,
                            icon: Icons.event_outlined,
                          ),
                        if (overdue)
                          _pill('Lewat', Colors.red.shade700, Colors.white),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // Butang padam
            IconButton(
              icon: Icon(Icons.delete_outline, color: Colors.grey.shade600),
              onPressed: () => _confirmDelete(doc.reference),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- Skrin utama ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.pink,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(
          widget.title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Tambah'),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const SecondPage()),
          );
        },
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _items.orderBy('createdAt', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final allDocs = snapshot.data!.docs;

          // Kira ringkasan (semua item yang belum settle)
          int pendingCount = 0;
          double pendingCost = 0;
          for (final d in allDocs) {
            final data = d.data();
            if (data['done'] != true) {
              pendingCount++;
              pendingCost += (data['cost'] as num?)?.toDouble() ?? 0;
            }
          }

          // Tapis senarai ikut pilihan
          final docs = allDocs.where((d) {
            final data = d.data();
            final done = data['done'] == true;
            switch (_filter) {
              case 'pending':
                return !done;
              case 'return':
                return data['type'] == 'return';
              case 'buy':
                return data['type'] == 'buy';
              default:
                return true;
            }
          }).toList();

          return Column(
            children: [
              // Header ringkasan
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                decoration: const BoxDecoration(
                  color: Colors.pink,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(30),
                    bottomRight: Radius.circular(30),
                  ),
                ),
                child: Row(
                  children: [
                    _statBox(Icons.pending_actions, '$pendingCount',
                        'Belum settle'),
                    const SizedBox(width: 12),
                    _statBox(Icons.account_balance_wallet_outlined,
                        'RM ${pendingCost.toStringAsFixed(2)}', 'Kos tertunggak'),
                  ],
                ),
              ),
              // Penapis
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: Row(
                  children: [
                    _filterChip('pending', 'Belum settle'),
                    _filterChip('all', 'Semua'),
                    _filterChip('return', 'Pulang'),
                    _filterChip('buy', 'Beli'),
                  ],
                ),
              ),
              // Senarai
              Expanded(
                child: docs.isEmpty
                    ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inventory_2_outlined,
                          size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 8),
                      Text('Tiada item',
                          style: TextStyle(color: Colors.grey.shade600)),
                    ],
                  ),
                )
                    : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 90),
                  itemCount: docs.length,
                  itemBuilder: (context, i) => _buildItemCard(docs[i]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}