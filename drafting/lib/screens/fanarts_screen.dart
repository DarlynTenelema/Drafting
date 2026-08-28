import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';
import '../core/models/fanart_model.dart';
import '../core/services/fanart_service.dart';
import '../core/services/creator_service.dart';
import 'upload_fanart_screen.dart';
import 'fanart_detail_screen.dart';
import 'creator_setup_screen.dart';

class FanartsScreen extends StatefulWidget {
  const FanartsScreen({super.key});

  @override
  State<FanartsScreen> createState() => _FanartsScreenState();
}

class _FanartsScreenState extends State<FanartsScreen> {
  int _selectedFilterIndex = 0;
  final List<String> _filters = ['Todos', 'Tendencias', 'Nuevos', 'Campeones', 'Emotes'];

  List<FanartModel> _allFanarts = [];
  List<FanartModel> _fanarts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFanarts();
  }

  Future<void> _loadFanarts() async {
    try {
      final results = await FanartService().getFanarts();
      if (mounted) {
        setState(() {
          _allFanarts = results;
          _applyFilter();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cargando fanarts: $e')),
        );
      }
    }
  }

  void _applyFilter() {
    if (_selectedFilterIndex == 0) {
      _fanarts = List.from(_allFanarts);
    } else {
      final filterTag = _filters[_selectedFilterIndex];
      _fanarts = _allFanarts.where((f) => f.tags.contains(filterTag)).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 60.0),
        child: FloatingActionButton(
          heroTag: 'add_fanart',
          onPressed: () async {
            // Mostrar indicador de carga mientras verificamos el perfil
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
            );

            final profile = await CreatorService().getCreatorProfile();
            
            if (!context.mounted) return;
            Navigator.pop(context); // cerrar indicador

            if (profile != null) {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const UploadFanartScreen()),
              ).then((value) {
                if (value == true) {
                  _loadFanarts();
                }
              });
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const CreatorSetupScreen()),
              ).then((value) {
                _loadFanarts();
              });
            }
          },
          backgroundColor: AppTheme.primary,
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            _buildFilters(),
            Expanded(
              child: _isLoading 
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                : _fanarts.isEmpty
                    ? const Center(child: Text('No hay fanarts disponibles', style: TextStyle(color: Colors.white)))
                    : _buildMasonryGrid(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      child: Text(
        'Mercado de Fanarts',
        style: GoogleFonts.outfit(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _filters.length,
        itemBuilder: (context, index) {
          final isSelected = _selectedFilterIndex == index;
          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedFilterIndex = index;
                _applyFilter();
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.primary : AppTheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? Colors.transparent : Colors.white.withValues(alpha: 0.1),
                ),
                boxShadow: isSelected
                    ? [BoxShadow(color: AppTheme.primary.withValues(alpha: 0.4), blurRadius: 8, offset: const Offset(0, 4))]
                    : [],
              ),
              child: Center(
                child: Text(
                  _filters[index],
                  style: GoogleFonts.inter(
                    color: isSelected ? Colors.white : AppTheme.textMuted,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMasonryGrid() {
    return MasonryGridView.count(
      padding: const EdgeInsets.all(16),
      crossAxisCount: 2,
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      itemCount: _fanarts.length,
      itemBuilder: (context, index) {
        return _FanartCard(fanart: _fanarts[index]);
      },
    );
  }
}

class _FanartCard extends StatefulWidget {
  final FanartModel fanart;

  const _FanartCard({required this.fanart});

  @override
  State<_FanartCard> createState() => _FanartCardState();
}

class _FanartCardState extends State<_FanartCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        // Simulación de Analíticas
        debugPrint('Analytics: Clic registrado. Tags: ${widget.fanart.tags}');
        
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => FanartDetailScreen(fanart: widget.fanart),
          ),
        );
      },
      onTapCancel: () => _controller.reverse(),
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) => Transform.scale(
          scale: _scaleAnimation.value,
          child: child,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              // Image
              AspectRatio(
                aspectRatio: widget.fanart.aspectRatio,
                child: CachedNetworkImage(
                  imageUrl: widget.fanart.imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    color: AppTheme.surface,
                    child: const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: AppTheme.surface,
                    child: const Icon(Icons.error, color: Colors.white),
                  ),
                ),
              ),

              // Bottom Glassmorphism Bar
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.3),
                        border: Border(
                          top: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 1),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Avatar & Name
                          Expanded(
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 12,
                                  backgroundImage: NetworkImage(widget.fanart.creatorAvatar),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    widget.fanart.creatorName,
                                    style: GoogleFonts.inter(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Price
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFD700).withValues(alpha: 0.2), // Gold tint
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.5)),
                            ),
                            child: Row(
                              children: [
                                Image.asset('assets/images/crystal_coin_outline.png', width: 14, height: 14),
                                const SizedBox(width: 4),
                                Text(
                                  '${widget.fanart.priceCoin.toInt()}',
                                  style: GoogleFonts.inter(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
