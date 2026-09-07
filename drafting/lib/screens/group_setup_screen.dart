import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../core/constants/app_constants.dart';
import '../theme/app_theme.dart';
import 'entrepreneur_dashboard_screen.dart';
import 'legal_screen.dart';
import '../core/services/entrepreneur_service.dart';

class GroupSetupScreen extends StatefulWidget {
  final String planName;
  final double price;
  final bool isGroup;
  final String? planId;
  final Map<String, dynamic>? draftGroup;

  const GroupSetupScreen({
    super.key,
    required this.planName,
    required this.price,
    required this.isGroup,
    this.planId,
    this.draftGroup,
  });

  @override
  State<GroupSetupScreen> createState() => _GroupSetupScreenState();
}

class InvitedMember {
  final String email;
  bool accepted;
  String status;
  InvitedMember(this.email, {this.accepted = false, this.status = 'pending'});
}

class _GroupSetupScreenState extends State<GroupSetupScreen> {
  // Goals
  late int _targetMembers;
  late int _targetChampions;

  // State
  final List<InvitedMember> _invitedMembers = [];
  final Map<String, Map<String, dynamic>> _configuredChampions = {};
  
  final TextEditingController _emailController = TextEditingController();
  String _selectedChampion = 'Ahri';

  // Form Controllers
  final _earlyGameCtrl = TextEditingController();
  final _lateGameCtrl = TextEditingController();
  final _situationalCtrl = TextEditingController();
  final _synergiesCtrl = TextEditingController();
  final _countersCtrl = TextEditingController();
  final _buildCtrl = TextEditingController();
  final _runesCtrl = TextEditingController();

  final List<String> _availableChampions = AppConstants.wildRiftChampions;

  // Product State
  final TextEditingController _productNameCtrl = TextEditingController();
  File? _productImageFile;
  final ImagePicker _picker = ImagePicker();

  bool _hasReadTerms = false;
  bool _acceptedTerms = false;
  bool _isEligible = false; // By default false, will check backend
  bool _isAdmin = false;

  // IAP
  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  late StreamSubscription<List<PurchaseDetails>> _purchaseSubscription;
  String _purchaseToken = '';
  bool _isPurchasing = false;
  BuildContext? _loadingContext;

  @override
  void initState() {
    super.initState();
    
    if (!widget.isGroup) {
      _targetMembers = 0;
      _targetChampions = 2; // OTP
    } else {
      final String id = widget.planId?.toString() ?? '';
      if (id.contains('300')) {
        _targetMembers = 15;
        _targetChampions = 90;
      } else if (id.contains('500')) {
        _targetMembers = 20;
        _targetChampions = AppConstants.totalWildRiftChampions;
      } else {
        _targetMembers = 5;
        _targetChampions = 30;
      }
    }

    _purchaseSubscription = _inAppPurchase.purchaseStream.listen(
      _listenToPurchaseUpdated,
      onDone: () => _purchaseSubscription.cancel(),
      onError: (error) {
        debugPrint('Purchase error: $error');
      },
    );

    _checkEligibility();
    
    // Load from draft if available
    if (widget.draftGroup != null) {
      final draft = widget.draftGroup!;
      _productNameCtrl.text = draft['product_name'] ?? draft['ProductName'] ?? '';
      
      final invitations = draft['group_invitations'] ?? draft['GroupInvitations'];
      if (invitations != null) {
        for (var inv in invitations) {
          final String email = inv['email']?.toString() ?? inv['Email']?.toString() ?? '';
          if (email.isNotEmpty) {
            String invStatus = (inv['status'] ?? inv['Status'])?.toString() ?? 'pending';
            _invitedMembers.add(InvitedMember(email, accepted: invStatus == 'accepted', status: invStatus));
          }
        }
      }

      // Load configured champions if available
      final privateDataRaw = draft['private_json_data'] ?? draft['PrivateJSONData'];
      if (privateDataRaw != null) {
        try {
          final Map<String, dynamic> parsed = json.decode(privateDataRaw);
          if (parsed.containsKey('champions')) {
            final champions = parsed['champions'] as Map<String, dynamic>;
            champions.forEach((k, v) {
              _configuredChampions[k] = Map<String, dynamic>.from(v);
            });
          }
        } catch (e) {
          debugPrint('Error parsing draft private data: $e');
        }
      }
    }
  }

  void _checkEligibility() async {
    final eligible = await EntrepreneurService().checkFirstTimeEligibility();
    final isAdmin = await EntrepreneurService().checkIsAdmin();
    if (mounted) {
      setState(() {
        _isEligible = eligible;
        _isAdmin = isAdmin;
      });
    }
  }

  String? _draftId;

  Future<bool> _autoSaveDraft() async {
    if (!widget.isGroup) return true; // Only drafts for groups

    if (_draftId == null && widget.draftGroup != null) {
      _draftId = widget.draftGroup!['id'] ?? widget.draftGroup!['ID'];
    }

    final Map<String, dynamic> privateData = {
      'champions': _configuredChampions,
    };

    final data = {
      'name': _productNameCtrl.text.isEmpty ? 'Borrador sin nombre' : _productNameCtrl.text,
      'product_name': _productNameCtrl.text,
      'description': '',
      'subscription_plan': widget.planId ?? widget.planName,
      'invites': _invitedMembers.map((e) => e.email).toList(),
      'private_json_data': json.encode(privateData),
    };

    if (_draftId == null) {
      final res = await EntrepreneurService().createGroupDraft(data['name'] as String, data['subscription_plan'] as String);
      if (res['success']) {
        _draftId = res['data']['id'] ?? res['data']['ID'];
        if (_draftId != null) {
           await EntrepreneurService().updateGroupDraft(_draftId!, data);
        }
        return true;
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al crear borrador: ${res['error']}')));
        return false;
      }
    } else {
      final res = await EntrepreneurService().updateGroupDraft(_draftId!, data);
      if (res['success'] == false) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al actualizar borrador: ${res['error']}')));
        return false;
      }
      return true;
    }
  }

  void _listenToPurchaseUpdated(List<PurchaseDetails> purchaseDetailsList) async {
    for (final purchaseDetails in purchaseDetailsList) {
      try {
        if (purchaseDetails.status == PurchaseStatus.pending) {
          continue;
        }

        if (purchaseDetails.status == PurchaseStatus.error) {
          if (_loadingContext != null) { Navigator.pop(_loadingContext!); _loadingContext = null; }
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(purchaseDetails.error?.message ?? 'Error en la compra')));
          setState(() => _isPurchasing = false);
          continue;
        }

        if (purchaseDetails.status == PurchaseStatus.canceled) {
          if (_loadingContext != null) { Navigator.pop(_loadingContext!); _loadingContext = null; }
          setState(() => _isPurchasing = false);
          continue;
        }

        if (purchaseDetails.status == PurchaseStatus.purchased || purchaseDetails.status == PurchaseStatus.restored) {
          _purchaseToken = purchaseDetails.verificationData.serverVerificationData;
          
          // Proceder con la creación solo si el usuario inició explícitamente el flujo
          if (_isPurchasing) {
            await _executeCreationFlow(purchaseDetails);
          } else if (purchaseDetails.status == PurchaseStatus.restored) {
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Suscripción previa restaurada. Ya puedes crear el plan.')));
          }
        }
      } catch (e) {
        debugPrint("Error fatal en _listenToPurchaseUpdated: $e");
        if (_loadingContext != null) { Navigator.pop(_loadingContext!); _loadingContext = null; }
        setState(() => _isPurchasing = false);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ocurrió un error procesando tu pago. Intenta de nuevo.')));
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _earlyGameCtrl.dispose();
    _lateGameCtrl.dispose();
    _situationalCtrl.dispose();
    _synergiesCtrl.dispose();
    _countersCtrl.dispose();
    _buildCtrl.dispose();
    _runesCtrl.dispose();
    _productNameCtrl.dispose();
    _purchaseSubscription.cancel();
    super.dispose();
  }

  int get _acceptedMembersCount => _invitedMembers.where((m) => m.accepted).length;
  bool get _isMembersGoalMet => _acceptedMembersCount >= _targetMembers;
  bool get _isChampionsGoalMet => _configuredChampions.length >= _targetChampions;
  bool get _isProductConfigured => _productNameCtrl.text.isNotEmpty && _productImageFile != null;
  bool get _canProceed => (_isAdmin || (_isMembersGoalMet && _isChampionsGoalMet)) && _isProductConfigured;

  void _inviteMember() async {
    final email = _emailController.text.trim();
    if (email.isNotEmpty && email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verificando usuario...')),
      );

      final isValid = await EntrepreneurService().validateInviteEmail(email);
      if (!mounted) return;

      if (isValid) {
        setState(() {
          _invitedMembers.add(InvitedMember(email));
          _emailController.clear();
        });
        _autoSaveDraft();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Usuario verificado e invitado. Pasa al Buzón de Emprender.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error: No hay ningún usuario registrado con ese correo.'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  void _saveChampion() async {
    if (_configuredChampions.containsKey(_selectedChampion)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ya configuraste a $_selectedChampion.')),
      );
      return;
    }
    
    if (_earlyGameCtrl.text.isEmpty ||
        _lateGameCtrl.text.isEmpty ||
        _synergiesCtrl.text.isEmpty ||
        _countersCtrl.text.isEmpty ||
        _runesCtrl.text.isEmpty ||
        _buildCtrl.text.isEmpty ||
        _situationalCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor completa todos los campos de la estrategia para asegurar la calidad de la IA.')),
      );
      return;
    }

    final Map<String, dynamic> championData = {
      'champion_name': _selectedChampion,
      'early_game_strategy': _earlyGameCtrl.text,
      'late_game_strategy': _lateGameCtrl.text,
      'synergies': _synergiesCtrl.text,
      'counters': _countersCtrl.text,
      'core_build': _buildCtrl.text,
      'spells_and_runes': _runesCtrl.text,
      'situational_items': _situationalCtrl.text,
    };

    // Muestra que está analizando
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Analizando textos con IA de Moderación...')),
    );

    // We can simulate passing the concatenated text to the moderation backend, or just send the Map.
    // For now, EntrepreneurService().saveAIModel performs the same moderation in the backend!
    final result = await EntrepreneurService().saveAIModel(championData);
    if (!mounted) return;

    if (result['success'] == true) {
      setState(() {
        _configuredChampions[_selectedChampion] = championData;
      });
      _autoSaveDraft();
      
      _earlyGameCtrl.clear();
      _lateGameCtrl.clear();
      _synergiesCtrl.clear();
      _countersCtrl.clear();
      _buildCtrl.clear();
      _runesCtrl.clear();
      _situationalCtrl.clear();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('¡Conocimiento de $_selectedChampion guardado y aprobado!')),
      );
    } else {
      bool isBanned = result['banned'] == true;
      String message = result['message']?.toString() ?? 'Error desconocido';
      if (isBanned || message.toLowerCase().contains('strike') || message.toLowerCase().contains('infracción')) {
        _showStrikeWarning(message, isBanned);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showStrikeWarning(String message, bool isBanned) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: isBanned ? Colors.red : Colors.orange),
            const SizedBox(width: 8),
            Text(
              isBanned ? 'Cuenta Suspendida' : 'Advertencia de Infracción',
              style: GoogleFonts.outfit(color: isBanned ? Colors.red : Colors.orange, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              if (isBanned) {
                // Logout user and redirect to login
                Navigator.of(context).pushReplacementNamed('/login');
              }
            },
            child: const Text('Entendido', style: TextStyle(color: AppTheme.primary)),
          ),
        ],
      ),
    );
  }

  void _showContractModal() async {
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    bool eligible = await EntrepreneurService().checkFirstTimeEligibility();
    if (mounted) {
      Navigator.pop(context); // Close loading
    }

    _hasReadTerms = false;
    _acceptedTerms = false;
    _isEligible = eligible;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext modalContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Contratar ${widget.planName}',
                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Total a pagar: \$${widget.price}',
                    style: GoogleFonts.inter(color: AppTheme.primary, fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 24),
                  
                  // Terms validation
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _hasReadTerms ? AppTheme.primary.withValues(alpha: 0.5) : Colors.redAccent.withValues(alpha: 0.5)),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Por políticas de transparencia, es obligatorio leer las condiciones de distribución de ganancias antes de contratar.',
                          style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 13),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.description),
                            label: const Text('Leer Términos y Condiciones'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white24),
                            ),
                            onPressed: () async {
                              final read = await Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const LegalScreen()),
                              );
                              if (read == true) {
                                setModalState(() {
                                  _hasReadTerms = true;
                                });
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  Row(
                    children: [
                      Checkbox(
                        value: _acceptedTerms,
                        activeColor: AppTheme.primary,
                        onChanged: _hasReadTerms 
                            ? (val) {
                                setModalState(() {
                                  _acceptedTerms = val ?? false;
                                });
                              }
                            : null,
                      ),
                      Expanded(
                        child: Text(
                          'He leído y acepto los términos de distribución de ganancias y costos API.',
                          style: GoogleFonts.inter(
                            color: _hasReadTerms ? Colors.white : AppTheme.textMuted, 
                            fontSize: 13
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 32),
                  
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _acceptedTerms 
                          ? () async {
                              if (_isPurchasing) return;
                              if (!_isEligible) {
                                // Iniciar pago real
                                setState(() => _isPurchasing = true);
                                showDialog(
                                  context: context, 
                                  barrierDismissible: false, 
                                  builder: (ctx) {
                                    _loadingContext = ctx;
                                    return const Center(child: CircularProgressIndicator());
                                  }
                                );

                                final bool isAvailable = await _inAppPurchase.isAvailable();
                                if (!isAvailable) {
                                  if (_loadingContext != null) { Navigator.pop(_loadingContext!); _loadingContext = null; }
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tienda no disponible')));
                                  setState(() => _isPurchasing = false);
                                  return;
                                }

                                String productId = _getProductId();

                                final response = await _inAppPurchase.queryProductDetails({productId});
                                if (response.productDetails.isEmpty) {
                                  if (_loadingContext != null) { Navigator.pop(_loadingContext!); _loadingContext = null; }
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Producto $productId no encontrado en la tienda. Verifica que el plan básico esté activo.')));
                                  setState(() => _isPurchasing = false);
                                  return;
                                }
                                
                                final purchaseParam = PurchaseParam(productDetails: response.productDetails.first);
                                try {
                                  final bool started = await _inAppPurchase.buyNonConsumable(purchaseParam: purchaseParam);
                                  if (!started) {
                                    if (_loadingContext != null) { Navigator.pop(_loadingContext!); _loadingContext = null; }
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo iniciar el proceso de compra con Google Play.')));
                                    setState(() => _isPurchasing = false);
                                  }
                                } catch (e) {
                                  if (_loadingContext != null) { Navigator.pop(_loadingContext!); _loadingContext = null; }
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al iniciar la compra: $e')));
                                  setState(() => _isPurchasing = false);
                                }
                              } else {
                                // Show Loading for creation
                                showDialog(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (ctx) {
                                    _loadingContext = ctx;
                                    return const Center(child: CircularProgressIndicator());
                                  }
                                );
                                await _executeCreationFlow();
                              }
                            } 
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        disabledBackgroundColor: Colors.white12,
                      ),
                      child: Text(_isEligible ? 'Comenzar Mes Gratis' : 'Pagar \$${widget.price} para Iniciar', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        title: Text(
          'Requisitos de Desbloqueo',
          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          if (widget.isGroup)
            TextButton.icon(
              onPressed: () async {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Guardando borrador...')));
                bool success = await _autoSaveDraft();
                if (success && mounted) {
                  Navigator.of(context).pop();
                }
              },
              icon: const Icon(Icons.save, color: Colors.orange),
              label: const Text('Guardar y Salir', style: TextStyle(color: Colors.orange)),
            ),
        ],
      ),
      body: Column(
        children: [
          // Header Progress
          Container(
            padding: const EdgeInsets.all(20),
            color: AppTheme.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Plan: ${widget.planName}',
                  style: GoogleFonts.inter(color: AppTheme.primary, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Para acceder a tu primer mes gratis, debes demostrar tu compromiso completando tu base de datos${widget.isGroup ? ' y armando tu equipo.' : '.'}',
                  style: GoogleFonts.inter(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 16),
                if (widget.isGroup) ...[
                  _buildProgressBar('Integrantes Aceptados', _acceptedMembersCount, _targetMembers),
                  const SizedBox(height: 12),
                ],
                _buildProgressBar('Campeones Configurados', _configuredChampions.length, _targetChampions),
              ],
            ),
          ),
          
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.isGroup) ...[
                    _buildSectionTitle(Icons.group_add, '1. Invitar Integrantes'),
                    Text('Envía invitaciones al correo registrado de tus compañeros. Google verificará su existencia.', style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 13)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _emailController,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: 'correo@ejemplo.com',
                              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                              filled: true,
                              fillColor: AppTheme.surface,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: _inviteMember,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Icon(Icons.send, color: Colors.white),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_invitedMembers.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: _invitedMembers.map((member) => ListTile(
                            leading: Icon(member.accepted ? Icons.check_circle : (member.status == 'declined' ? Icons.cancel : Icons.access_time), color: member.accepted ? Colors.green : (member.status == 'declined' ? Colors.redAccent : Colors.amber)),
                            title: Text(member.email, style: const TextStyle(color: Colors.white)),
                            subtitle: Text(member.accepted ? 'Aceptado' : (member.status == 'declined' ? 'Rechazado' : 'Pendiente'), style: TextStyle(color: member.accepted ? Colors.green : (member.status == 'declined' ? Colors.redAccent : Colors.amber), fontSize: 12)),
                            trailing: IconButton(
                              icon: const Icon(Icons.close, color: Colors.redAccent),
                              onPressed: () {
                                setState(() {
                                  _invitedMembers.remove(member);
                                });
                                _autoSaveDraft();
                              },
                            ),
                            onTap: null,
                          )).toList(),
                        ),
                      ),
                    
                    const SizedBox(height: 40),
                  ],

                  _buildSectionTitle(Icons.psychology, widget.isGroup ? '2. Base de Datos IA' : '1. Base de Datos IA'),
                  Text('Entrena a tu modelo completando fichas técnicas detalladas.', style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 13)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.shield, color: Colors.orange, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'La IA analiza todo lo que escribes. Usa términos de juego libremente (ej. "matar", "explotar"), pero amenazas, insultos graves o contenido sexual explicito resultarán en strikes inmediatos.',
                            style: GoogleFonts.inter(color: Colors.orange, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Autocomplete Campeón
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Autocomplete<String>(
                      initialValue: TextEditingValue(text: _selectedChampion),
                      optionsBuilder: (TextEditingValue textEditingValue) {
                        if (textEditingValue.text == '') {
                          return _availableChampions;
                        }
                        return _availableChampions.where((String option) {
                          return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
                        });
                      },
                      onSelected: (String selection) {
                        setState(() { _selectedChampion = selection; });
                      },
                      fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
                        return TextField(
                          controller: textEditingController,
                          focusNode: focusNode,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            hintText: 'Buscar campeón...',
                            hintStyle: TextStyle(color: Colors.white30),
                            border: InputBorder.none,
                            icon: Icon(Icons.search, color: Colors.white30),
                          ),
                        );
                      },
                      optionsViewBuilder: (context, onSelected, options) {
                        return Align(
                          alignment: Alignment.topLeft,
                          child: Material(
                            color: AppTheme.surface,
                            elevation: 4.0,
                            borderRadius: BorderRadius.circular(12),
                            child: SizedBox(
                              width: MediaQuery.of(context).size.width - 48,
                              child: ListView.builder(
                                padding: const EdgeInsets.all(8.0),
                                shrinkWrap: true,
                                itemCount: options.length,
                                itemBuilder: (BuildContext context, int index) {
                                  final String option = options.elementAt(index);
                                  return GestureDetector(
                                    onTap: () {
                                      onSelected(option);
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(16.0),
                                      child: Text(option, style: const TextStyle(color: Colors.white)),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  _buildTextField('Estrategia de Early Game (Min 0-10)', _earlyGameCtrl, 'Ej. Jugar pasivo hasta nivel 5...'),
                  _buildTextField('Estrategia de Late Game', _lateGameCtrl, 'Ej. Hacer peel al ADC, buscar flancos...'),
                  _buildTextField('Mejores Aliados (Sinergias)', _synergiesCtrl, 'Ej. Malphite, Amumu, Nami...'),
                  _buildTextField('Counters (Peores enfrentamientos)', _countersCtrl, 'Ej. Zed, Fizz, Kassadin...'),
                  _buildTextField('Hechizos y Runas Principales', _runesCtrl, 'Ej. Flash, Ignición, Electrocutar...'),
                  _buildTextField('Build Principal (Objetos Core)', _buildCtrl, 'Ej. Luden, Sombrero de Rabadon...'),
                  _buildTextField('Objetos Situacionales', _situationalCtrl, 'Ej. Cortacuras, Zhonya (contra asesinos)...'),
                  
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton.icon(
                      onPressed: _saveChampion,
                      icon: const Icon(Icons.save),
                      label: const Text('Guardar Conocimiento del Campeón'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primary,
                        side: const BorderSide(color: AppTheme.primary),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 40),
                  
                  _buildSectionTitle(Icons.store, '3. Perfil Comercial (Tienda)'),
                  Text('Este es el nombre e imagen que verán los usuarios en la Tienda al querer comprar tu producto.', style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 13)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.gpp_maybe, color: Colors.redAccent, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'POLÍTICA ESTRICTA: Las imágenes de perfiles son moderadas sin tolerancia. Prohibido desnudos, material sugerente o gore. Usa fondos de paisajes, renders o logos. Romper esta regla penaliza tu cuenta.',
                            style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  _buildTextField('Nombre del Producto (Ej. Ahri OTP Mastery)', _productNameCtrl, 'Escribe un nombre atractivo...'),
                  const SizedBox(height: 12),
                  Text('Imagen del Producto', style: GoogleFonts.inter(color: Colors.white70, fontSize: 14)),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () async {
                      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
                      if (image != null) {
                        setState(() {
                          _productImageFile = File(image.path);
                        });
                      }
                    },
                    child: Container(
                      height: 150,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: _productImageFile != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(_productImageFile!, fit: BoxFit.cover),
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.add_photo_alternate, color: Colors.white30, size: 40),
                                const SizedBox(height: 8),
                                Text('Toca para subir imagen', style: GoogleFonts.inter(color: Colors.white30, fontSize: 14)),
                              ],
                            ),
                    ),
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
          
          // Bottom Bar
          Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: AppTheme.surface,
              boxShadow: [BoxShadow(color: Colors.black26, offset: Offset(0, -4), blurRadius: 10)],
            ),
            child: SafeArea(
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _canProceed ? _showContractModal : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    disabledBackgroundColor: Colors.white12,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Text(
                    _canProceed ? 'Proceder al Contrato' : 'Misiones Incompletas',
                    style: GoogleFonts.inter(
                      fontSize: 16, 
                      fontWeight: FontWeight.bold,
                      color: _canProceed ? Colors.white : Colors.white38,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _executeCreationFlow(PurchaseDetails purchaseDetails) async {
    try {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Paso 1: Subiendo imagen a Supabase...')));
      
      // Upload Image
      String? imageUrl = await EntrepreneurService().uploadProductImage(_productImageFile!, 'temp_user');
      
      if (imageUrl == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error: No se pudo subir la imagen del producto.')));
        setState(() => _isPurchasing = false);
        return;
      }

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Paso 2: Creando perfil en el servidor...')));

      Map<String, dynamic> result;
      if (widget.isGroup) {
        if (_draftId == null) await _autoSaveDraft();
        if (_draftId == null) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error: No se pudo guardar el borrador.')));
          setState(() => _isPurchasing = false);
          return;
        }
        
        // Update draft with image first
        await EntrepreneurService().updateGroupDraft(_draftId!, {
          'name': _productNameCtrl.text,
          'product_name': _productNameCtrl.text,
          'product_image': imageUrl,
          'description': '',
          'subscription_plan': widget.planId ?? widget.planName,
          'invites': _invitedMembers.map((e) => e.email).toList(),
        });

        final reqData = {
          'purchase_token': _purchaseToken,
          'product_id': _getProductId(),
          'purchase_price': widget.price,
        };
        result = await EntrepreneurService().publishGroupDraft(_draftId!, reqData);
      } else {
        result = await EntrepreneurService().createOTPProfile(_configuredChampions.keys.first, widget.price.toString(), _getProductId(), _productNameCtrl.text, imageUrl, _purchaseToken);
      }

      if (result['success'] == true) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Paso 3: Guardando configuraciones...')));
        
        // AI models were already saved incrementally via _saveChampion.
        // If we want to link them or do something else, we can do it here.
        // For now, they are safely stored in the AIModel table.
        
        if (purchaseDetails.pendingCompletePurchase) {
          try {
            await _inAppPurchase.completePurchase(purchaseDetails).timeout(const Duration(seconds: 15));
          } catch (e) {
            debugPrint("Error completando la compra nativa: $e");
          }
        }

        if (mounted) {
          if (_loadingContext != null) {
            Navigator.pop(_loadingContext!);
            _loadingContext = null;
          }
          Navigator.pop(context); // Close modal
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const EntrepreneurDashboardScreen()),
          );
        }
      } else {
        if (mounted) {
          if (_loadingContext != null) {
            Navigator.pop(_loadingContext!);
            _loadingContext = null;
          }
          bool isBanned = result['banned'] == true;
          String errorMsg = result['error']?.toString() ?? 'Error desconocido';
          if (isBanned || errorMsg.toLowerCase().contains('strike') || errorMsg.toLowerCase().contains('infracción')) {
            _showStrikeWarning(errorMsg, isBanned);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error del backend: $errorMsg'), duration: const Duration(seconds: 5)),
            );
          }
          setState(() => _isPurchasing = false);
        }
      }
    } catch (e) {
      debugPrint("Error in _executeCreationFlow: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error inesperado: $e')),
        );
        setState(() => _isPurchasing = false);
      }
    } finally {
      if (_loadingContext != null) { 
        Navigator.pop(_loadingContext!); 
        _loadingContext = null; 
      }
    }
  }

  String _getProductId() {
    if (widget.isGroup) {
      if (widget.planName.contains('Start')) return 'emp_grupo_basico_100';
      if (widget.planName.contains('Avanzado')) return 'emp_grupo_pro_300';
      if (widget.planName.contains('Elite')) return 'emp_grupo_enterprise_500';
      return 'emp_grupo_basico_100';
    } else {
      if (widget.planName.contains('Básico')) return 'emp_otp_basico_10';
      if (widget.planName.contains('Pro')) return 'emp_otp_pro_30';
      if (widget.planName.contains('Leyenda')) return 'emp_otp_enterprise_50';
      return 'emp_otp_basico_10';
    }
  }

  Widget _buildProgressBar(String label, int current, int total) {
    double progress = total > 0 ? (current / total).clamp(0.0, 1.0) : 1.0;
    bool isDone = progress >= 1.0;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
            Text('$current / $total', style: GoogleFonts.outfit(color: isDone ? Colors.green : AppTheme.primary, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: progress,
          backgroundColor: Colors.white12,
          color: isDone ? Colors.green : AppTheme.primary,
          minHeight: 8,
          borderRadius: BorderRadius.circular(4),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 24),
          const SizedBox(width: 8),
          Text(title, style: GoogleFonts.outfit(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, String hint) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.inter(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            maxLines: 2,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
              filled: true,
              fillColor: AppTheme.background,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary)),
            ),
          ),
        ],
      ),
    );
  }
}
