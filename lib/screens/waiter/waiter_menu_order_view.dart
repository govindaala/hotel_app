import 'package:flutter/material.dart';
import '../../Data/Menu_data_source.dart';

class WaiterMenuOrderView extends StatefulWidget {
  final Function(MenuItemModel item) onAddItem;

  const WaiterMenuOrderView({super.key, required this.onAddItem});

  @override
  State<WaiterMenuOrderView> createState() => _WaiterMenuOrderViewState();
}

class _WaiterMenuOrderViewState extends State<WaiterMenuOrderView> {
  String _selectedCategory = 'सभी (All)';
  String _searchQuery = '';

  List<MenuItemModel> get _filteredItems {
    return kRestaurantMenu.where((item) {
      final matchesCategory = _selectedCategory == 'सभी (All)' || item.category == _selectedCategory;
      final matchesSearch = item.name.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesCategory && matchesSearch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 1. सर्च बार
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'मेन्यू आइटम खोजें...',
              prefixIcon: const Icon(Icons.search),
              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onChanged: (val) {
              setState(() {
                _searchQuery = val.trim();
              });
            },
          ),
        ),

        // 2. कैटेगरी फ़िल्टर चिप्स
        SizedBox(
          height: 46,
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
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? Colors.white : Colors.black87,
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: Colors.deepOrange,
                  backgroundColor: Colors.grey.shade200,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _selectedCategory = cat;
                      });
                    }
                  },
                ),
              );
            },
          ),
        ),

        const Divider(height: 1),

        // 3. फ़िल्टर की गई मेन्यू लिस्ट
        Expanded(
          child: ListView.separated(
            itemCount: _filteredItems.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = _filteredItems[index];
              return ListTile(
                dense: true,
                title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                subtitle: Text(item.category, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('₹${item.price.toStringAsFixed(0)}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87)),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.add_circle, color: Colors.green, size: 28),
                      onPressed: () => widget.onAddItem(item),
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
