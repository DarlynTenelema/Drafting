import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/api_client.dart';

/// Mixin con herencia de estado y lógica común para los analizadores de Draft con IA
/// (`LolPcScannerScreen` y `ManualDraftScreen`).
/// Elimina la duplicación del parser Regex de campeones vistos, estados de carga y manejo de cuotas (HTTP 402).
mixin DraftAnalyzerStateMixin<T extends StatefulWidget> on State<T> {
  bool isAnalyzing = false;
  bool isRefreshing = false;
  String? recommendationText;
  String? errorMessage;
  final List<String> seenChampions = [];

  /// Extrae los nombres de campeones recomendados en el texto devuelto por la IA
  /// para poder excluirlos cuando el usuario solicita "Reconsultar Alternativas".
  @protected
  void extractSeenChampions(String text) {
    final regA = RegExp(r'(?:PLAN|PLANO)\s*A\s*:\s*([^•\n\r]+)', caseSensitive: false);
    final matchA = regA.firstMatch(text);
    if (matchA != null) {
      final name = matchA.group(1)?.trim();
      if (name != null && name.isNotEmpty && !seenChampions.contains(name)) {
        seenChampions.add(name);
      }
    }
    final regSim = RegExp(r'•\s*([^:\n\r]+):', caseSensitive: false);
    for (final m in regSim.allMatches(text)) {
      final name = m.group(1)?.trim();
      if (name != null && name.isNotEmpty && !seenChampions.contains(name)) {
        final lower = name.toLowerCase();
        if (!lower.contains('hechizo') &&
            !lower.contains('runa') &&
            !lower.contains('plan') &&
            !lower.contains('por qué') &&
            !lower.contains('por que') &&
            !lower.contains('spell') &&
            !lower.contains('feitiço') &&
            !lower.contains('sort') &&
            !lower.contains('build')) {
          seenChampions.add(name);
        }
      }
    }
  }

  /// Limpia la recomendación actual y el historial de campeones vistos.
  @protected
  void resetAnalysisState() {
    recommendationText = null;
    errorMessage = null;
    seenChampions.clear();
  }

  /// Ejecuta la petición HTTP de análisis al backend con manejo unificado de estados,
  /// exclusión de campeones repetidos en refresh y detección de saldo agotado (402).
  @protected
  Future<void> runDraftAnalysisRequest({
    required String endpoint,
    required Map<String, dynamic> bodyData,
    required int availableQueries,
    required VoidCallback onDataChanged,
    required VoidCallback onNoQueries,
    bool isRefresh = false,
    String connectionErrorPrefix = 'Error de conexión',
    bool lightHapticOnSuccess = false,
  }) async {
    if (isAnalyzing) return;

    if (availableQueries <= 0) {
      onNoQueries();
      return;
    }

    setState(() {
      isAnalyzing = true;
      isRefreshing = isRefresh;
      errorMessage = null;
    });

    try {
      if (isRefresh && seenChampions.isNotEmpty) {
        bodyData['exclude_champions'] = seenChampions.join(', ');
      }

      final res = await ApiClient.post(
        endpoint,
        authenticated: true,
        body: bodyData,
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) {
          final rec = (data['recommendation'] as String?) ?? 'Sin recomendación clara.';
          extractSeenChampions(rec);
          setState(() {
            recommendationText = rec;
            isAnalyzing = false;
            isRefreshing = false;
          });
          onDataChanged();
          if (lightHapticOnSuccess) {
            HapticFeedback.lightImpact();
          } else {
            HapticFeedback.mediumImpact();
          }
        }
      } else if (res.statusCode == 402) {
        if (mounted) {
          setState(() {
            isAnalyzing = false;
            isRefreshing = false;
          });
          onNoQueries();
        }
      } else {
        if (mounted) {
          setState(() {
            isAnalyzing = false;
            isRefreshing = false;
            errorMessage = 'Error del servidor (${res.statusCode}): ${res.body}';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isAnalyzing = false;
          isRefreshing = false;
          errorMessage = '$connectionErrorPrefix: $e';
        });
      }
    }
  }
}
