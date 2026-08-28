import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/models/video_model.dart';
import '../core/services/video_service.dart';
import '../theme/app_theme.dart';
import 'videos_screen.dart'; // For VideoCard

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  List<VideoModel> _searchResults = [];
  bool _isLoading = false;
  String _lastQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isLoading = false;
        _lastQuery = '';
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (_lastQuery != query.trim()) {
        _performSearch(query.trim());
      }
    });
  }

  Future<void> _performSearch(String query) async {
    setState(() {
      _isLoading = true;
      _lastQuery = query;
    });

    final results = await VideoService().searchVideos(query);
    
    if (mounted) {
      setState(() {
        _searchResults = results;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: TextField(
          controller: _searchController,
          style: const TextStyle(color: Colors.white),
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Buscar videos, canales, etiquetas...',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
            border: InputBorder.none,
          ),
          onChanged: _onSearchChanged,
        ),
        actions: [
          if (_searchController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear, color: Colors.white),
              onPressed: () {
                _searchController.clear();
                _onSearchChanged('');
              },
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }

    if (_searchController.text.trim().isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 64, color: Colors.white.withValues(alpha: 0.2)),
            const SizedBox(height: 16),
            Text(
              'Escribe algo para buscar',
              style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 16),
            ),
          ],
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.sentiment_dissatisfied, size: 64, color: Colors.white.withValues(alpha: 0.2)),
            const SizedBox(height: 16),
            Text(
              'No se encontraron resultados para "$_lastQuery"',
              style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      itemCount: _searchResults.length,
      separatorBuilder: (context, index) => const SizedBox(height: 24),
      itemBuilder: (context, index) {
        return VideoCard(video: _searchResults[index]);
      },
    );
  }
}
