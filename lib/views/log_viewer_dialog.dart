import 'package:flutter/material.dart';

import '../compress_logger.dart';

final class LogViewerDialog extends StatefulWidget {
  const LogViewerDialog({super.key});

  @override
  State<LogViewerDialog> createState() => _LogViewerDialogState();
}

class _LogViewerDialogState extends State<LogViewerDialog> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  String _filter = '';

  @override
  void initState() {
    super.initState();
    CompressLogger().addListener(_onLog);
    _scrollToBottom();
  }

  @override
  void dispose() {
    CompressLogger().removeListener(_onLog);
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onLog() {
    if (!_searching) {
      _scrollToBottom();
    }
    setState(() {});
  }

  bool get _searching => _filter.isNotEmpty;

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final entries = CompressLogger().entries;
    final filtered = _filter.isEmpty
        ? entries
        : entries
            .where((e) => e.plainLine.toLowerCase().contains(_filter.toLowerCase()))
            .toList();

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        width: 800,
        constraints: const BoxConstraints(maxHeight: 700),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            _buildHeader(cs),
            _buildSearchBar(cs),
            const Divider(height: 1),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        _filter.isEmpty ? 'Нет записей' : 'Ничего не найдено',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      itemCount: filtered.length,
                      itemBuilder: (context, i) => _LogLine(
                        entry: filtered[i],
                        cs: cs,
                      ),
                    ),
            ),
            _buildFooter(cs, filtered.length, entries.length),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 8, 0),
      child: Row(
        children: [
          Icon(Icons.terminal, size: 20, color: cs.onSurface),
          const SizedBox(width: 10),
          Text(
            'Журнал событий',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: cs.onSurface,
            ),
          ),
          const Spacer(),
          SizedBox(
            width: 36,
            height: 36,
            child: IconButton(
              icon: Icon(Icons.delete_outline, size: 18),
              tooltip: 'Очистить',
              onPressed: () {
                setState(() {
                  CompressLogger().entries.clear();
                });
              },
              style: IconButton.styleFrom(
                foregroundColor: cs.onSurfaceVariant,
              ),
            ),
          ),
          SizedBox(
            width: 36,
            height: 36,
            child: IconButton(
              icon: Icon(Icons.close, size: 20),
              tooltip: 'Закрыть',
              onPressed: () => Navigator.of(context).pop(),
              style: IconButton.styleFrom(
                foregroundColor: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: SizedBox(
        height: 36,
        child: TextField(
          controller: _searchController,
          style: TextStyle(fontSize: 13, color: cs.onSurface),
          decoration: InputDecoration(
            hintText: 'Поиск...',
            hintStyle: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            prefixIcon: Icon(Icons.search, size: 16, color: cs.onSurfaceVariant),
            suffixIcon: _filter.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.clear, size: 16),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _filter = '');
                      _scrollToBottom();
                    },
                  )
                : null,
            contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: cs.outline),
            ),
            filled: true,
            fillColor: cs.surfaceContainerHighest,
            isDense: true,
          ),
          onChanged: (v) => setState(() => _filter = v),
        ),
      ),
    );
  }

  Widget _buildFooter(ColorScheme cs, int shown, int total) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      child: Row(
        children: [
          Text(
            _filter.isEmpty ? '$total записей' : 'Показано $shown из $total',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

final class _LogLine extends StatelessWidget {
  final LogEntry entry;
  final ColorScheme cs;

  const _LogLine({required this.entry, required this.cs});

  Color _colorForLevel(LogLevel level) {
    return switch (level) {
      LogLevel.debug => const Color(0xFF5B9BD5),
      LogLevel.success => const Color(0xFF27AE60),
      LogLevel.process => const Color(0xFF00BCD4),
      LogLevel.warning => const Color(0xFFF39C12),
      LogLevel.error => const Color(0xFFE74C3C),
    };
  }

  @override
  Widget build(BuildContext context) {
    final color = _colorForLevel(entry.level);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 18,
            margin: const EdgeInsets.only(top: 3, right: 8),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: SelectableText(
              entry.plainLine,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: entry.level == LogLevel.warning ||
                        entry.level == LogLevel.error
                    ? color
                    : cs.onSurface,
                fontWeight: entry.level == LogLevel.warning ||
                        entry.level == LogLevel.error
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
