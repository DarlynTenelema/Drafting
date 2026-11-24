import 'package:flutter/material.dart';
import '../../core/services/language_service.dart';

/// Mixin reutilizable para pantallas StatefulWidget que necesitan reaccionar
/// automáticamente a cambios de idioma sin duplicar listeners en initState/dispose.
mixin LocalizedStateMixin<T extends StatefulWidget> on State<T> {
  LanguageService get lang => LanguageService.instance;

  String tr(String key, [Map<String, String>? params]) => lang.tr(key, params);

  @override
  void initState() {
    super.initState();
    LanguageService.instance.languageNotifier.addListener(_handleLanguageChangeInternal);
  }

  @override
  void dispose() {
    LanguageService.instance.languageNotifier.removeListener(_handleLanguageChangeInternal);
    super.dispose();
  }

  void _handleLanguageChangeInternal() {
    if (!mounted) return;
    onLanguageChanged();
    setState(() {});
  }

  /// Hook opcional para subclases que además de reconstruir la UI necesiten
  /// recargar datos del backend en el nuevo idioma.
  @protected
  void onLanguageChanged() {}
}
