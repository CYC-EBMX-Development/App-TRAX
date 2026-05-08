class Product {
  final String? id;
  final String name;
  final String? description;
  final double price;
  final String? imageUrl;
  final String category; // new, secondhand
  final String type; // conversion_kit, accessory

  Product({
    this.id,
    required this.name,
    this.description,
    required this.price,
    this.imageUrl,
    this.category = 'new',
    this.type = 'conversion_kit',
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id']?.toString(),
      name: json['name'] ?? '',
      description: json['description'],
      price: (json['price'] as num?)?.toDouble() ?? 0,
      imageUrl: json['imageUrl'],
      category: json['category'] ?? 'new',
      type: json['type'] ?? 'conversion_kit',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'price': price,
        'imageUrl': imageUrl,
        'category': category,
        'type': type,
      };
}
