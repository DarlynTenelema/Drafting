import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Barra superior ("drag handle") estándar de los ModalBottomSheets Hextech.
class HextechSheetHandle extends StatelessWidget {
  final double width;
  final double height;

  const HextechSheetHandle({
    super.key,
    this.width = 40,
    this.height = 4,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white24,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// Contenedor envolvente con estilo Hextech (borde neón cian y sombra superior)
/// usado en los modales inferiores de la app.
class HextechBottomSheetContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const HextechBottomSheetContainer({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(22, 16, 22, 26),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(
          color: AppTheme.hextechCyan.withValues(alpha: 0.35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.hextechCyan.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: child,
      ),
    );
  }
}

/// Chip selector expandido reutilizable para selectores horizontales en modales
/// (ej. modos de admin en Eventos o selector de plataformas en Donaciones).
class HextechSelectableChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color activeColor;
  final VoidCallback onTap;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final TextStyle? textStyle;

  const HextechSelectableChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.activeColor = AppTheme.hextechCyan,
    this.padding = const EdgeInsets.symmetric(vertical: 8),
    this.borderRadius = 10,
    this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(borderRadius),
        child: Container(
          padding: padding,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? activeColor.withValues(alpha: 0.2)
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: selected ? activeColor : Colors.white12,
              width: selected ? 1.5 : 1.0,
            ),
          ),
          child: Text(
            label,
            style: textStyle ??
                TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: selected ? activeColor : Colors.white70,
                ),
          ),
        ),
      ),
    );
  }
}
