import 'package:flutter/material.dart';

class ModelImageCard extends StatefulWidget {
  final String? imageUrl;
  final String modelName;

  const ModelImageCard({
    Key? key,
    required this.imageUrl,
    required this.modelName,
  }) : super(key: key);

  @override
  State<ModelImageCard> createState() => _ModelImageCardState();
}

class _ModelImageCardState extends State<ModelImageCard> {
  bool _hasError = false;
  bool _isLoading = true;

  @override
  void didUpdateWidget(ModelImageCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _hasError = false;
      _isLoading = true;
    }
  }

  void _onImageError(Object error, StackTrace? stackTrace) {
    if (mounted) {
      setState(() {
        _hasError = true;
        _isLoading = false;
      });
    }
  }

  void _onImageLoaded(ImageProvider image, bool synchronousCall) {
    if (mounted) {
      setState(() {
        _isLoading = false;
        _hasError = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!, width: 1),
      ),
      child: _buildImageContent(),
    );
  }

  Widget _buildImageContent() {
    final imageUrl = widget.imageUrl;

    if (imageUrl == null || imageUrl.isEmpty) {
      return _buildPlaceholder('No image available');
    }

    if (_hasError) {
      return _buildPlaceholder('Failed to load image');
    }

    // Build full image URL for relative paths
    final fullImageUrl = imageUrl.startsWith('http')
        ? imageUrl
        : 'http://localhost:8080$imageUrl';

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            fullImageUrl,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _onImageError(error, stackTrace);
              });
              return _buildPlaceholder('Failed to load');
            },
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    setState(() {
                      _isLoading = false;
                      _hasError = false;
                    });
                  }
                });
                return child;
              }
              return Center(
                child: CircularProgressIndicator(
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded /
                          (loadingProgress.expectedTotalBytes ?? 1)
                      : null,
                  strokeWidth: 2,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder(String message) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_not_supported, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              message,
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
