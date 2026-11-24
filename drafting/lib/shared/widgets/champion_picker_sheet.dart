import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/app_constants.dart';
import '../../theme/app_theme.dart';
import 'hextech_ui.dart';

/// Modal reutilizable de búsqueda y selección de campeones de Wild Rift.
/// Usado tanto en `ManualDraftScreen` como en el selector OTP de `IndexScreen`.
class ChampionPickerSheet extends StatefulWidget {
  final String title;
  final String? selectedChampion;
  final ValueChanged<String> onSelected;
  final String searchHint;
  final Widget? leadingHeaderIcon;
  final VoidCallback? onClear;
  final double heightFactor;

  const ChampionPickerSheet({
    super.key,
    required this.title,
    required this.selectedChampion,
    required this.onSelected,
    this.searchHint = 'Buscar campeón (ej. Zed, Yasuo, Ahri)...',
    this.leadingHeaderIcon,
    this.onClear,
    this.heightFactor = 0.75,
  });

  @override
  State<ChampionPickerSheet> createState() => _ChampionPickerSheetState();
}

class _ChampionPickerSheetState extends State<ChampionPickerSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<String> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = AppConstants.wildRiftChampions;
    _searchCtrl.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final query = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filtered = AppConstants.wildRiftChampions;
      } else {
        _filtered = AppConstants.wildRiftChampions
            .where((c) => c.toLowerCase().contains(query))
            .toList();
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * widget.heightFactor,
      decoration: const BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          const HextechSheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
            child: Row(
              children: [
                if (widget.leadingHeaderIcon != null) ...[
                  widget.leadingHeaderIcon!,
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    widget.title,
                    style: GoogleFonts.outfit(
                      fontSize: widget.leadingHeaderIcon != null ? 16 : 17,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                if (widget.onClear != null)
                  TextButton(
                    onPressed: widget.onClear,
                    child: const Text('Limpiar', style: TextStyle(color: Colors.redAccent)),
                  )
                else
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white60),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: widget.searchHint,
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.hextechCyan),
                filled: true,
                fillColor: AppTheme.surface,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              itemCount: _filtered.length,
              itemBuilder: (ctx, idx) {
                final champ = _filtered[idx];
                final isSelected = champ == widget.selectedChampion;
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  tileColor: isSelected ? AppTheme.hextechCyan.withValues(alpha: 0.12) : null,
                  leading: CircleAvatar(
                    backgroundColor: isSelected ? AppTheme.hextechCyan : AppTheme.surface,
                    radius: 18,
                    child: Text(
                      champ.substring(0, 1),
                      style: TextStyle(
                        color: isSelected ? AppTheme.deepDarkBg : Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(
                    champ,
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected ? AppTheme.hextechCyan : Colors.white,
                    ),
                  ),
                  trailing: isSelected
                      ? const Icon(Icons.check_circle_rounded, color: AppTheme.hextechCyan, size: 20)
                      : null,
                  onTap: () => widget.onSelected(champ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
