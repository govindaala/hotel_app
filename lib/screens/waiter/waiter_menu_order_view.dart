import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../Data/Menu_data_source.dart';

class WaiterMenuOrderView extends StatefulWidget {
  final Function(MenuItemModel item) onAddItem;
  final Function(MenuItemModel item)? onRemoveItem;
  final Map<dynamic, int>? cart;
  final List<MenuItemModel>? menuList;

  const WaiterMenuOrderView({
    super.key,
    required this.onAddItem,
    this.onRemoveItem,
    this.cart,
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
  final Map<dynamic, int> _localCart = {};

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
    List<MenuItemModel> baseList = widget.menuList ?? List.from(kRestaurantMenu);

    final prefs = await SharedPreferences.getInstance();
    final cachedStatuses = prefs.getStringList('cached_menu_stock_disabled') ?? [];
    final Map<String, bool> statusMap = {};

    for (var id in cachedStatuses) {
      statusMap[id] = false;
    }

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

  int _getItemCount(dynamic id) {
    if (widget.cart != null) {
      return widget.cart![id] ?? 0;
    }
    return _localCart[id] ?? 0;
  }

  void _handleIncrease(MenuItemModel item) {
    widget.onAddItem(item);
    setState(() {
      _localCart[item.id] = (_localCart[item.id] ?? 0) + 1;
    });
  }

  void _handleDecrease(MenuItemModel item) {
    if (widget.onRemoveItem != null) {
      widget.onRemoveItem!(item);
    }
    setState(() {
      final cur = _getItemCount(item.id);
      if (cur > 1) {
        _localCart[item.id] = cur - 1;
      } else {
        _localCart.remove(item.id);
      }
    });
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
                    final int qty = _getItemCount(item.id);

                    return ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
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
                          const SizedBox(width: 8),
                          Text(
                            '₹${item.price.toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: isAvailable ? Colors.green.shade800 : Colors.grey,
                            ),
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
                      trailing: isAvailable
                          ? (qty == 0
                              ? ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF0F172A),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8)),
                                    elevation: 0,
                                  ),
                                  icon: const Icon(Icons.add,
                                      size: 16, color: Colors.white),
                                  label: const Text('जोड़ें',
                                      style: TextStyle(
                                          color: Colors.white, fontSize: 12)),
                                  onPressed: () => _handleIncrease(item),
                                )
                              : Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: const Color(0xFFCBD5E1)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      InkWell(
                                        onTap: () => _handleDecrease(item),
                                        borderRadius: const BorderRadius.horizontal(
                                            left: Radius.circular(8)),
                                        child: const Padding(
                                          padding: EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 6),
                                          child: Icon(Icons.remove,
                                              size: 18, color: Colors.redAccent),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 6),
                                        color: Colors.white,
                                        child: Text(
                                          '$qty',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color: Color(0xFF0F172A),
                                          ),
                                        ),
                                      ),
                                      InkWell(
                                        onTap: () => _handleIncrease(item),
                                        borderRadius: const BorderRadius.horizontal(
                                            right: Radius.circular(8)),
                                        child: const Padding(
                                          padding: EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 6),
                                          child: Icon(Icons.add,
                                              size: 18, color: Colors.green),
                                        ),
                                      ),
                                    ],
                                  ),
                                ))
                          : const Icon(Icons.block, color: Colors.grey, size: 22),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
