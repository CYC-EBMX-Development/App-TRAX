import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'package:trax_app/common/widgets/page_code_badge.dart';

class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final _products = [
    _ProductData('BAFANG BBS02B Kit', 'Mid-drive motor 750W conversion kit', 459.99, 'new'),
    _ProductData('Tongsheng TSDZ2', '48V torque sensor mid-drive kit', 389.00, 'new'),
    _ProductData('Voilamart 26" Kit', 'Rear hub motor 1000W conversion', 299.99, 'new'),
    _ProductData('Used Bafang BBSHD', '1000W mid-drive, 500km used', 320.00, 'secondhand'),
    _ProductData('Swytch Kit', 'Universal front wheel conversion', 199.99, 'secondhand'),
    _ProductData('CYC X1 Pro Gen3', 'High-performance mid-drive', 699.00, 'new'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PageCodeBadge(code: '500', child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Shop', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [IconButton(icon: const Icon(Icons.shopping_cart_outlined), onPressed: () {})],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          tabs: const [Tab(text: 'All'), Tab(text: 'Brand New'), Tab(text: 'Second Hand')],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildProductGrid(_products),
          _buildProductGrid(_products.where((p) => p.category == 'new').toList()),
          _buildProductGrid(_products.where((p) => p.category == 'secondhand').toList()),
        ],
      ),
    );
  }

  Widget _buildProductGrid(List<_ProductData> products) {
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, childAspectRatio: 0.72, crossAxisSpacing: 12, mainAxisSpacing: 12,
      ),
      itemCount: products.length,
      itemBuilder: (context, index) => _ProductCard(product: products[index]),
    );
  }
}

class _ProductData {
  final String name, description, category;
  final double price;
  _ProductData(this.name, this.description, this.price, this.category);
}

class _ProductCard extends StatelessWidget {
  final _ProductData product;
  const _ProductCard({required this.product});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Container(
              width: double.infinity,
              color: AppColors.background,
              child: Stack(
                children: [
                  Center(child: Icon(Icons.electric_bike, size: 48, color: AppColors.primary.withValues(alpha: 0.4))),
                  if (product.category == 'secondhand')
                    Positioned(
                      top: 8, left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(4)),
                        child: const Text('Used', style: TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w600)),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text('\$${product.price.toStringAsFixed(2)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.primary)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
