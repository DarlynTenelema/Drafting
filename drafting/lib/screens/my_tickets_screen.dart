import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/services/session_service.dart';
import '../theme/app_theme.dart';
import '../core/config/app_config.dart';
import 'create_ticket_screen.dart';
import 'ticket_chat_screen.dart';

class MyTicketsScreen extends StatefulWidget {
  const MyTicketsScreen({super.key});

  @override
  State<MyTicketsScreen> createState() => _MyTicketsScreenState();
}

class _MyTicketsScreenState extends State<MyTicketsScreen> {
  List<dynamic> _tickets = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchTickets();
  }

  Future<void> _fetchTickets() async {
    setState(() => _isLoading = true);
    try {
      final token = await SessionService.getSessionToken();
      // En entorno de desarrollo local usaríamos 10.0.2.2 o la IP correspondiente
      final response = await http.get(
        AppConfig.apiUri('/api/v1/support/tickets'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        setState(() {
          _tickets = json.decode(response.body);
        });
      }
    } catch (e) {
      debugPrint('Error fetching tickets: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'open':
        return Colors.orangeAccent;
      case 'in_progress':
        return Colors.purpleAccent;
      case 'resolved':
        return Colors.greenAccent;
      default:
        return Colors.grey;
    }
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'open':
        return 'Pendiente';
      case 'in_progress':
        return 'En Proceso';
      case 'resolved':
        return 'Resuelto';
      default:
        return 'Cerrado';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text('Mis Reportes', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        backgroundColor: AppTheme.surface,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _tickets.isEmpty
              ? _buildEmptyState()
              : _buildList(),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'create_ticket',
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreateTicketScreen()),
          );
          if (result == true) {
            _fetchTickets(); // Refresh if new ticket created
          }
        },
        backgroundColor: AppTheme.accent,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo Reporte', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long, size: 80, color: Colors.white.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          Text(
            'No tienes reportes activos',
            style: GoogleFonts.outfit(fontSize: 20, color: Colors.white70),
          ),
          const SizedBox(height: 8),
          const Text(
            'Si tienes un problema o detectas\nun fraude, repórtalo aquí.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _tickets.length,
      itemBuilder: (context, index) {
        final t = _tickets[index];
        final statusColor = _getStatusColor(t['status']);
        
        return Card(
          color: AppTheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.only(bottom: 16),
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            title: Text(t['subject'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: statusColor),
                    ),
                    child: Text(
                      _getStatusLabel(t['status']),
                      style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    t['ticket_type'].toString().toUpperCase(),
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.white54),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => TicketChatScreen(ticket: t)),
              );
            },
          ),
        );
      },
    );
  }
}
