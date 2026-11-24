import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class SecondPage extends StatefulWidget {
  const SecondPage({super.key});

  @override
  State<SecondPage> createState() => _SecondPageState();
}

class _SecondPageState extends State<SecondPage> {
  final _formKey = GlobalKey<FormState>();
  final _itemCtrl = TextEditingController();
  final _partyCtrl = TextEditingController();
  final _costCtrl = TextEditingController();

  String _type = 'return'; // return atau buy
  DateTime? _dueDate;
  bool _saving = false;

  @override
  void dispose() {
    _itemCtrl.dispose();
    _partyCtrl.dispose();
    _costCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final cost = double.tryParse(_costCtrl.text.trim().replaceAll(',', '.'));

    try {
      await FirebaseFirestore.instance.collection('logistics').add({
        'item': _itemCtrl.text.trim(),
        'type': _type,
        'party': _partyCtrl.text.trim(),
        'cost': cost,
        'dueDate': _dueDate == null ? null : Timestamp.fromDate(_dueDate!),
        'done': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal simpan: $e')),
        );
      }
    }
  }

  // Gaya input yang sama untuk semua kotak teks
  InputDecoration _inputStyle(String label, IconData icon, {String? prefix}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: Colors.pink),
      prefixText: prefix,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.pink, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isBuy = _type == 'buy';
    final dateText = _dueDate == null
        ? 'Tarikh (pilihan)'
        : '${_dueDate!.day.toString().padLeft(2, '0')}/'
        '${_dueDate!.month.toString().padLeft(2, '0')}/${_dueDate!.year}';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.pink,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Tambah Item',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Pilih jenis
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: 'return',
                    label: Text('Kena pulang'),
                    icon: Icon(Icons.assignment_return_outlined),
                  ),
                  ButtonSegment(
                    value: 'buy',
                    label: Text('Kena beli'),
                    icon: Icon(Icons.shopping_cart_outlined),
                  ),
                ],
                selected: {_type},
                onSelectionChanged: (s) => setState(() => _type = s.first),
              ),
              const SizedBox(height: 24),

              TextFormField(
                controller: _itemCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: _inputStyle('Nama barang', Icons.inventory_2_outlined),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Sila isi nama barang'
                    : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _partyCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: _inputStyle(
                  isBuy ? 'Beli di mana / kedai' : 'Pulang kepada siapa / kelab',
                  isBuy ? Icons.storefront_outlined : Icons.groups_outlined,
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Sila isi maklumat ini'
                    : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _costCtrl,
                keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
                decoration: _inputStyle(
                    'Kos (pilihan)', Icons.payments_outlined,
                    prefix: 'RM '),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  return double.tryParse(v.trim().replaceAll(',', '.')) == null
                      ? 'Masukkan nombor yang sah'
                      : null;
                },
              ),
              const SizedBox(height: 16),

              // Pilih tarikh
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(14),
                child: InputDecorator(
                  decoration: _inputStyle('Tarikh akhir', Icons.event_outlined),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          dateText,
                          style: TextStyle(
                            fontSize: 16,
                            color: _dueDate == null
                                ? Colors.grey.shade600
                                : Colors.black87,
                          ),
                        ),
                      ),
                      if (_dueDate != null)
                        GestureDetector(
                          onTap: () => setState(() => _dueDate = null),
                          child: const Icon(Icons.close, size: 20),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // Butang simpan
              FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.pink,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                    : const Text('Simpan', style: TextStyle(fontSize: 18)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
