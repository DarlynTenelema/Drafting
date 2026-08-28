import 'dart:io';
import 'dart:async';
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

  const GroupSetupScreen({
    super.key,
    required this.planName,
    required this.price,
    required this.isGroup,
  });

  @override
  State<GroupSetupScreen> createState() => _GroupSetupScreenState();
}

class InvitedMember {
  final String email;
  bool accepted;
  InvitedMember(this.email, {this.accepted = false});
}

class _GroupSetupScreenState extends State<GroupSetupScreen> {
  // Goals
  late int _targetMembers;
  late int _targetChampions;

  // State
  final List<InvitedMember> _invitedMembers = [];
  final Map<String, String> _configuredChampions = {};
  
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

  final List<String> _availableChampions = [
    'Ahri', 'Akali', 'Darius', 'Evelynn', 'Ezreal', 'Garen', 'Jinx', 
    'Lee Sin', 'Lux', 'Master Yi', 'Miss Fortune', 'Seraphine', 'Vi', 'Yasuo', 'Zed',
    'Annie', 'Ashe', 'Vayne', 'Teemo', 'Katarina'
  ]; // Muestra abreviada para UI

  // Product State
  final TextEditingController _productNameCtrl = TextEditingController();
  File? _productImageFile;
  final ImagePicker _picker = ImagePicker();

  bool _hasReadTerms = false;
  bool _acceptedTerms = false;
  bool _isEligible = true;

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
      if (widget.planName.contains('Start')) {
        _targetMembers = 5;
        _targetChampions = 30;
      } else if (widget.planName.contains('Avanzado') || widget.planName.contains('Pro')) {
        _targetMembers = 15;
        _targetChampions = 90;
      } else if (widget.planName.contains('Elite') || widget.planName.contains('Leyenda')) {
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
      onError: (_) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error en compra')));
      },
    );
  }

  void _listenToPurchaseUpdated(List<PurchaseDetails> purchaseDetailsList) async {
    for (final purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.status == PurchaseStatus.pending) {
        continue;
      }

      if (purchaseDetails.status == PurchaseStatus.error) {
        if (_loadingContext != null) { Navigator.pop(_loadingContext!); _loadingContext = null; }
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(purchaseDetails.error?.message ?? 'Error')));
        setState(() => _isPurchasing = false);
        continue;
      }

      if (purchaseDetails.status == PurchaseStatus.purchased || purchaseDetails.status == PurchaseStatus.restored) {
        _purchaseToken = purchaseDetails.verificationData.serverVerificationData;
        if (purchaseDetails.pendingCompletePurchase) {
          await _inAppPurchase.completePurchase(purchaseDetails);
        }
        
        // Proceder con la creación
        await _executeCreationFlow();
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

  int get _acceptedMembersCount => _invitedMembers.length;
  bool get _isMembersGoalMet => _invitedMembers.length >= _targetMembers;
  bool get _isChampionsGoalMet => _configuredChampions.length >= _targetChampions;
  bool get _isProductConfigured => _productNameCtrl.text.isNotEmpty && _productImageFile != null;
  bool get _canProceed => _isMembersGoalMet && _isChampionsGoalMet && _isProductConfigured;

  void _inviteMember() {
    final email = _emailController.text.trim();
    if (email.isNotEmpty && email.contains('@')) {
      setState(() {
        // En demo, la primera invitación siempre la marcamos como "aceptada" al tocar para simular
        _invitedMembers.add(InvitedMember(email));
        _emailController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invitación enviada. (Toca el correo en la lista para simular que aceptaron)')),
      );
    }
  }

  void _saveChampion() {
    if (_configuredChampions.containsKey(_selectedChampion)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ya configuraste a $_selectedChampion.')),
      );
      return;
    }
    
    if (_earlyGameCtrl.text.isEmpty || _situationalCtrl.text.isEmpty || _buildCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Completa al menos Early Game, Build y Situacionales.')),
      );
      return;
    }

    final rules = """
Early Game: ${_earlyGameCtrl.text}
Late Game: ${_lateGameCtrl.text}
Synergies: ${_synergiesCtrl.text}
Counters: ${_countersCtrl.text}
Build: ${_buildCtrl.text}
Runes/Spells: ${_runesCtrl.text}
Situational: ${_situationalCtrl.text}
""";

    setState(() {
      _configuredChampions[_selectedChampion] = rules;
      _earlyGameCtrl.clear();
      _lateGameCtrl.clear();
      _situationalCtrl.clear();
      _synergiesCtrl.clear();
      _countersCtrl.clear();
      _buildCtrl.clear();
      _runesCtrl.clear();
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('¡$_selectedChampion guardado exitosamente!')),
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

                                // Simular el ID del producto basado en el plan
                                String productId = widget.isGroup ? 'creator_group_${widget.planName.toLowerCase()}' : 'creator_otp_${widget.planName.toLowerCase()}';
                                // Como es un MVP y los IDs tal vez no existan, usaremos un mock o intentaremos query
                                final response = await _inAppPurchase.queryProductDetails({productId, 'creator_test_product'});
                                if (response.productDetails.isEmpty) {
                                  // Fallback para pruebas si no hay productos reales configurados en la consola
                                  if (_loadingContext != null) { Navigator.pop(_loadingContext!); _loadingContext = null; }
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Producto no encontrado en la tienda. (Modo prueba activo)')));
                                  // Para pruebas locales, forzamos un token mock
                                  _purchaseToken = "mock_token_12345";
                                  await _executeCreationFlow();
                                  return;
                                }
                                
                                final purchaseParam = PurchaseParam(productDetails: response.productDetails.first);
                                await _inAppPurchase.buyNonConsumable(purchaseParam: purchaseParam);
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
                            leading: const Icon(Icons.access_time, color: Colors.amber),
                            title: Text(member.email, style: const TextStyle(color: Colors.white)),
                            subtitle: const Text('Pendiente', style: TextStyle(color: Colors.amber, fontSize: 12)),
                            onTap: null,
                          )).toList(),
                        ),
                      ),
                    
                    const SizedBox(height: 40),
                  ],

                  _buildSectionTitle(Icons.psychology, widget.isGroup ? '2. Base de Datos IA' : '1. Base de Datos IA'),
                  Text('Entrena a tu modelo completando fichas técnicas detalladas.', style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 13)),
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

  Future<void> _executeCreationFlow() async {
    // Upload Image
    String? imageUrl = await EntrepreneurService().uploadProductImage(_productImageFile!, 'temp_user');
    
    // Manejo de Error 4: Abortar si la imagen falla
    if (imageUrl == null) {
      if (_loadingContext != null) { Navigator.pop(_loadingContext!); _loadingContext = null; }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo subir la imagen del producto. Verifica tu conexión a internet.')));
      setState(() => _isPurchasing = false);
      return;
    }

    bool success = false;
    if (widget.isGroup) {
      final emails = _invitedMembers.map((e) => e.email).toList();
      success = await EntrepreneurService().createGroup('Grupo de ${widget.planName}', widget.price.toString(), emails, _productNameCtrl.text, imageUrl, _purchaseToken);
    } else {
      success = await EntrepreneurService().createOTPProfile(_configuredChampions.keys.first, widget.price.toString(), _productNameCtrl.text, imageUrl, _purchaseToken);
    }

    if (success) {
      // Save all champions
      for (var entry in _configuredChampions.entries) {
        await EntrepreneurService().saveChampionData(entry.key, entry.value);
      }
      
      if (mounted) {
        if (_loadingContext != null) { Navigator.pop(_loadingContext!); _loadingContext = null; } // Close loading
        Navigator.pop(context); // Close modal
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const EntrepreneurDashboardScreen()),
        );
      }
    } else {
      if (mounted) {
        if (_loadingContext != null) { Navigator.pop(_loadingContext!); _loadingContext = null; }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al crear el plan. Verifica que hayas completado todos los requisitos.')),
        );
        setState(() => _isPurchasing = false);
      }
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
