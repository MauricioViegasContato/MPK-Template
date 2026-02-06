import 'package:flutter/material.dart';
import 'dart:io';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/constants/app_colors.dart';

class PhotoActionButton extends StatelessWidget {
  final VoidCallback onTap;
  final String label;
  final List<File> imageFiles;
  final Function(File)? onRemove;

  const PhotoActionButton({
    super.key,
    required this.onTap,
    this.label = 'Tirar Foto do Comprovante',
    this.imageFiles = const [],
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    if (imageFiles.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 140,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: imageFiles.length + 1, // +1 for the Add button
              itemBuilder: (context, index) {
                if (index == imageFiles.length) {
                  // Add Button
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: InkWell(
                      onTap: onTap,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 100,
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[300]!, width: 2, style: BorderStyle.solid),
                        ),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_a_photo, color: Colors.grey),
                            SizedBox(height: 8),
                            Text('Adicionar', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                      ),
                    ),
                  );
                }

                final file = imageFiles[index];
                return Padding(
                  padding: const EdgeInsets.only(right: 12.0),
                  child: Stack(
                    alignment: Alignment.topRight,
                    children: [
                      Container(
                        width: 140,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          image: DecorationImage(
                            image: FileImage(file),
                            fit: BoxFit.cover,
                          ),
                          border: Border.all(color: AppColors.success.withOpacity(0.5), width: 1),
                        ),
                      ),
                      if (onRemove != null)
                        Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: CircleAvatar(
                            radius: 14,
                            backgroundColor: Colors.white,
                            child: IconButton(
                              icon: const Icon(Icons.close, color: Colors.red, size: 16),
                              padding: EdgeInsets.zero,
                              onPressed: () => onRemove!(file),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Text('${imageFiles.length} foto(s) anexada(s)', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
        ],
      );
    }

    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(16),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 32),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Theme.of(context).dividerColor, width: 2, style: BorderStyle.solid),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.secondary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.camera_alt, size: 40, color: AppColors.secondary),
              ),
              const SizedBox(height: 16),
              Text(
                label,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Toque para abrir a câmera',
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).hintColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
