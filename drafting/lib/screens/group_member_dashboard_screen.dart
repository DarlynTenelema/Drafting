import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/services/entrepreneur_service.dart';
import '../theme/app_theme.dart';
import 'member_upload_knowledge_screen.dart';

class GroupMemberDashboardScreen extends StatefulWidget {
  const GroupMemberDashboardScreen({super.key});

  @override
  State<GroupMemberDashboardScreen> createState() => _GroupMemberDashboardScreenState();
}

class _GroupMemberDashboardScreenState extends State<GroupMemberDashboardScreen> {
  Map<String, dynamic>? _groupData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadGroupData();
  }

  Future<void> _loadGroupData() async {
    setState(() => _isLoading = true);
    final data = await EntrepreneurService().getMyGroup();
    if (mounted) {
      setState(() {
        _groupData = data;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: Text('Mi Equipo', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          backgroundColor: AppTheme.surface,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_groupData == null || _groupData!['group'] == null) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: Text('Mi Equipo', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          backgroundColor: AppTheme.surface,
        ),
        body: Center(
          child: Text(
            'No perteneces a ningún grupo.',
            style: GoogleFonts.inter(color: Colors.white70, fontSize: 16),
          ),
        ),
      );
    }

    final group = _groupData!['group'];
    final members = _groupData!['members'] as List<dynamic>? ?? [];
    final isOwner = _groupData!['is_owner'] == true;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(group['Name'] ?? group['name'] ?? 'Mi Equipo', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        backgroundColor: AppTheme.surface,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Group Banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.primary, AppTheme.primaryDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Plan: ${group['SubscriptionPlan'] ?? group['subscription_plan'] ?? 'Desconocido'}',
                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    group['Description'] ?? group['description'] ?? 'Sin descripción',
                    style: GoogleFonts.inter(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            Text(
              'Tareas y Aportes',
              style: GoogleFonts.outfit(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Card(
              color: AppTheme.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppTheme.primary,
                  child: Icon(Icons.upload_file, color: Colors.white),
                ),
                title: Text('Subir Información (Entrenar IA)', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: Text('Sube reglas o datos para tus campeones asignados.', style: GoogleFonts.inter(color: Colors.white70)),
                trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 16),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MemberUploadKnowledgeScreen()),
                  );
                },
              ),
            ),
            
            const SizedBox(height: 24),
            Text(
              'Integrantes del Grupo',
              style: GoogleFonts.outfit(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...members.map((m) {
              return Card(
                color: AppTheme.surface,
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.white10,
                    child: Text(
                      (m['email'] ?? m['Email'] ?? '?')[0].toUpperCase(),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  title: Text(
                    m['email'] ?? m['Email'] ?? 'Usuario',
                    style: GoogleFonts.inter(color: Colors.white),
                  ),
                  subtitle: Text('Estado: Activo', style: GoogleFonts.inter(color: Colors.green)),
                ),
              );
            }).toList(),
            
            const SizedBox(height: 32),
            if (!isOwner)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Has abandonado el grupo con éxito.')),
                    );
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.exit_to_app, color: Colors.white),
                  label: Text('Abandonar Grupo', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
