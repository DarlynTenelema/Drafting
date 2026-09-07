import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/services/entrepreneur_service.dart';
import '../theme/app_theme.dart';

class InvitationsScreen extends StatefulWidget {
  const InvitationsScreen({super.key});

  @override
  State<InvitationsScreen> createState() => _InvitationsScreenState();
}

class _InvitationsScreenState extends State<InvitationsScreen> {
  List<Map<String, dynamic>> _invitations = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadInvitations();
  }

  Future<void> _loadInvitations() async {
    setState(() => _isLoading = true);
    final invitations = await EntrepreneurService().getMyInvitations();
    if (mounted) {
      setState(() {
        _invitations = invitations;
        _isLoading = false;
      });
    }
  }

  Future<void> _respond(String id, bool accept) async {
    final success = await EntrepreneurService().respondToInvitation(id, accept);
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(accept ? 'Invitación aceptada' : 'Invitación rechazada'),
          backgroundColor: accept ? Colors.green : Colors.red,
        ),
      );
      _loadInvitations();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error al procesar la invitación'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text('Buzón de Invitaciones', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        backgroundColor: AppTheme.surface,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _invitations.isEmpty
              ? Center(
                  child: Text(
                    'No tienes invitaciones pendientes',
                    style: GoogleFonts.inter(color: Colors.white54, fontSize: 16),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _invitations.length,
                  itemBuilder: (context, index) {
                    final inv = _invitations[index];
                    return Card(
                      color: AppTheme.surface,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: AppTheme.primary,
                          child: Icon(Icons.mail, color: Colors.white),
                        ),
                        title: Text(
                          'Invitación a Grupo',
                          style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          'Estado: ${inv['status'] ?? inv['Status'] ?? 'Pendiente'}',
                          style: GoogleFonts.inter(color: Colors.white70),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.redAccent),
                              onPressed: () => _respond(inv['id']?.toString() ?? inv['ID']?.toString() ?? '', false),
                            ),
                            IconButton(
                              icon: const Icon(Icons.check, color: Colors.green),
                              onPressed: () => _respond(inv['id']?.toString() ?? inv['ID']?.toString() ?? '', true),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
