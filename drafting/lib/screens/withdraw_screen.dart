import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/services/finance_service.dart';
import '../theme/app_theme.dart';

class WithdrawScreen extends StatefulWidget {
  final FinanceService financeService;
  
  const WithdrawScreen({super.key, required this.financeService});

  @override
  State<WithdrawScreen> createState() => _WithdrawScreenState();
}

class _WithdrawScreenState extends State<WithdrawScreen> {
  bool _isProcessing = false;

  Future<void> _handleWithdraw() async {
    if (widget.financeService.withdrawableUsd < widget.financeService.withdrawalLimit) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Debes alcanzar el mínimo de \$${widget.financeService.withdrawalLimit.toStringAsFixed(2)} para retirar.'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isProcessing = true);

    final success = await widget.financeService.withdrawFunds();

    if (mounted) {
      setState(() => _isProcessing = false);
      
      if (success) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            backgroundColor: AppTheme.surface,
            title: Text('Retiro en Proceso', style: GoogleFonts.outfit(color: Colors.white)),
            content: Text(
              'Hemos recibido tu solicitud de retiro.\n\nEl proceso de desembolso está en curso. Pronto te notificaremos y te pediremos tus datos bancarios para completar la transferencia segura.',
              style: GoogleFonts.inter(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context); // Close dialog
                  Navigator.pop(context, true); // Return to previous screen and refresh
                },
                child: const Text('Entendido', style: TextStyle(color: AppTheme.primary)),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al procesar la solicitud de retiro.'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Retirar Fondos', style: GoogleFonts.outfit(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Balance Disponible para Retiro',
              style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              '\$${widget.financeService.withdrawableUsd.toStringAsFixed(2)}',
              style: GoogleFonts.outfit(color: Colors.greenAccent, fontSize: 48, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Balance Total: \$${widget.financeService.totalUsd.toStringAsFixed(2)}',
              style: GoogleFonts.inter(color: Colors.white54, fontSize: 14),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: AppTheme.textMuted),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'El monto mínimo para solicitar un retiro es de \$${widget.financeService.withdrawalLimit.toStringAsFixed(2)} USD. Solo se pueden retirar los fondos que hayan superado el tiempo de retención de 30 días.',
                      style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.financeService.withdrawableUsd >= widget.financeService.withdrawalLimit ? AppTheme.primary : AppTheme.surface,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _isProcessing || widget.financeService.withdrawableUsd < widget.financeService.withdrawalLimit ? null : _handleWithdraw,
                child: _isProcessing
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : Text(
                        'Confirmar Retiro',
                        style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
