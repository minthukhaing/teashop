library teashop_pos.presentation.admin.screens.admin_shop_settings_screen;

import 'package:flutter/material.dart';

import '../../../data/database/app_database.dart';
import '../../../data/models/shop_settings.dart';
import '../../app_theme.dart';

/// Shop profile & billing settings: shop name, address and the government
/// tax percentage printed on POS vouchers/bills.
class AdminShopSettingsScreen extends StatefulWidget {
  const AdminShopSettingsScreen({super.key});

  @override
  State<AdminShopSettingsScreen> createState() => _AdminShopSettingsScreenState();
}

class _AdminShopSettingsScreenState extends State<AdminShopSettingsScreen> {
  final AppDatabase _db = AppDatabase.instance;
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _taxCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _taxCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = await _db.getShopSettings();
    if (!mounted) return;
    setState(() {
      _nameCtrl.text = settings.shopName;
      _addressCtrl.text = settings.shopAddress;
      _taxCtrl.text = settings.govTaxPercent.toStringAsFixed(1);
      _loading = false;
    });
  }

  Future<void> _save() async {
    final tax = double.tryParse(_taxCtrl.text.trim());
    if (_nameCtrl.text.trim().isEmpty) {
      _snack('Shop name is required.');
      return;
    }
    if (tax == null || tax < 0) {
      _snack('Enter a valid Gov Tax percentage (e.g. 5 or 5.0).');
      return;
    }
    setState(() => _saving = true);
    await _db.saveShopSettings(ShopSettings(
      shopName: _nameCtrl.text.trim(),
      shopAddress: _addressCtrl.text.trim(),
      govTaxPercent: tax,
    ));
    if (!mounted) return;
    setState(() => _saving = false);
    _snack('Shop settings saved.');
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            elevation: 2,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('🏪 Shop Information',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                      'Shown on every POS voucher / bill. The Gov Tax % is added on top of the sub-total.',
                      style:
                          TextStyle(fontSize: 12, color: AppColors.muted)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Shop Name',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.storefront_outlined, size: 20),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _addressCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Shop Address',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.location_on_outlined, size: 20),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _taxCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Gov Tax %',
                      hintText: 'e.g. 5',
                      border: OutlineInputBorder(),
                      prefixIcon:
                          Icon(Icons.percent_outlined, size: 20),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AdminColors.sidebarBg,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.save_outlined, size: 20),
                      label: const Text('Save Settings',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
