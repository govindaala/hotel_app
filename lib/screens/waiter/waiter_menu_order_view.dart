import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../Data/Menu_data_source.dart';

class WaiterMenuOrderView extends StatefulWidget {
  final Function(MenuItemModel item) onAddItem;
  final List<MenuItemModel>? menuList;

  const WaiterMenuOrderView({
    super.key,
    required this.onAddItem,
    this.menuList,
  });

  @override
  State<WaiterMenuOrderView> createState() => _WaiterMenuOrderViewState();
}

class _WaiterMenuOrderViewState extends State<WaiterMenuOrderView> {
  String _selectedCategory = 'सभी (All)';
  String _searchQuery = '';
  List<MenuItemModel> _activeMenu = [];
  Map<String, bool> _stockStatusMap = {};
  bool _hideOutOfStock = false;

  @override
  void initState() {
    super.initState();
    _initMenuData();
  }

  @override
  void didUpdateWidget(covariant WaiterMenuOrderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.menuList != oldWidget.menuList) {
      _initMenuData();
    }
  }

  Future<void> _initMenuData() async {
    // 1. अगर पैरेंट स्क्रीन ने लाइव मेन्यू दिया है तो वह लें, अन्यथा डिफ़ॉल्ट लिस्ट
    List<MenuItemModel> baseList = widget.menuList ?? List.from(kRestaurantMenu);

    // 2. लोकल कैश से उपलब्धता स्टेटस लोड करें (बिना इंटरनेट ऑफ़लाइन सुरक्षा)
    final prefs = await SharedPreferences.getInstance();
    final cachedStatuses = prefs.getStringList('cached_menu_stock_disabled') ?? [];
    final Map<String, bool> statusMap = {};

    for (var id in cachedStatuses) {
      statusMap[id] = false; // बंद आइटम
    }

    // 3. यदि इंटरनेट उपलब्ध हो तो Supabase से ताज़ा स्थिति सिंक करें
    try {
      final res = await Supabase.instance.client
          .from('menu_items')
          .select('id, is_available');

      List<String> disabledIds = [];
      for (var r in res) {
        final String id = r['id'].toString();
        final bool isAvail = r['is_available'] ?? true;
        statusMap[id] = isAvail;
        if (!isAvail) disabledIds.add(id);
      }
      await prefs.setStringList('cached_menu_stock_disabled', disabledIds);
    } catch (_) {}

    // मेन्यू में स्थिति अपडेट करें
    final updatedList = baseList.map((item) {
      final isAvailable = statusMap[item.id] ?? item.isAvailable;
      return item.copyWith(isAvailable: isAvailable);
    }).toList();

    if (mounted) {
      setState(() {
        _stockStatusMap = statusMap;
        _activeMenu = updatedList;
      });
    }
  }

  List<MenuItemModel> get _filteredItems {
    return _activeMenu.where((item) {
      final matchesCategory =
          _selectedCategory == 'सभी (All)' || item.category == _selectedCategory;
      final matchesSearch =
          item.name.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesAvailability = !_hideOutOfStock || item.isAvailable;

      return matchesCategory && matchesSearch && matchesAvailability;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 1. सर्च बार और फ़िल्टर टॉगल
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'व्यंजन खोजें (उदा. चाय, पराठा)...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val.trim()),
                ),
              ),
              const SizedBox(width: 6),
              FilterChip(
                label: const Text('उपलब्ध केवल', style: TextStyle(fontSize: 11)),
                selected: _hideOutOfStock,
                selectedColor: Colors.teal.shade100,
                onSelected: (val) => setState(() => _hideOutOfStock = val),
              ),
            ],
          ),
        ),

        // 2. श्रेणी फ़िल्टर चिप्स
        SizedBox(
          height: 44,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: kMenuCategories.length,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemBuilder: (context, index) {
              final cat = kMenuCategories[index];
              final isSelected = cat == _selectedCategory;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(
                    cat,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: const Color(0xFFEA580C),
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _selectedCategory = cat);
                    }
                  },
                ),
              );
            },
          ),
        ),

        const Divider(height: 1),

        // 3. मेन्यू लिस्ट (आउट-ऑफ-स्टॉक चेक के साथ)
        Expanded(
          child: _filteredItems.isEmpty
              ? const Center(
                  child: Text(
                    'कोई व्यंजन नहीं मिला',
                    style: TextStyle(color: Colors.black45),
                  ),
                )
              : ListView.separated(
                  itemCount: _filteredItems.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = _filteredItems[index];
                    final bool isAvailable = item.isAvailable;

                    return ListTile(
                      dense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                      title: Text(
                        item.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          decoration:
                              isAvailable ? null : TextDecoration.lineThrough,
                          color: isAvailable
                              ? const Color(0xFF0F172A)
                              : Colors.grey.shade500,
                        ),
                      ),
                      subtitle: Row(
                        children: [
                          Text(
                            item.category,
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade600),
                          ),
                          if (!isAvailable) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                    color: Colors.red.shade300, width: 0.8),
                              ),
                              child: Text(
                                'स्टॉक खत्म',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red.shade700),
                              ),
                            ),
                          ]
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '₹${item.price.toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: isAvailable
                                  ? const Color(0xFF0F172A)
                                  : Colors.grey,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: Icon(
                              isAvailable
                                  ? Icons.add_circle
                                  : Icons.remove_circle_outline,
                              color: isAvailable
                                  ? const Color(0xFF059669)
                                  : Colors.grey.shade400,
                              size: 28,
                            ),
                            onPressed: isAvailable
                                ? () => widget.onAddItem(item)
                                : () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                            '⚠️ "${item.name}" अभी स्टॉक में उपलब्ध नहीं है!'),
                                        backgroundColor: Colors.red.shade800,
                                        duration: const Duration(seconds: 2),
                                      ),
                                    );
                                  },
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
