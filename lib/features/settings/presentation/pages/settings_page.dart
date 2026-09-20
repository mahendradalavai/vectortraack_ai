import 'package:flutter/material.dart';

import 'package:kitten/core/ai/config/ai_config.dart';
import 'package:kitten/core/ai/models/ai_exception.dart';
import 'package:kitten/core/ai/providers/groq_provider.dart';
import 'package:kitten/core/services/secure_storage_service.dart';

/// Settings screen for Kitten AI.
///
/// Features functional Groq AI configuration (API key management, model selection,
/// connection testing) alongside placeholder sections for future capabilities.
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    this.secureStorage,
    this.groqProvider,
  });

  final SecureStorageService? secureStorage;
  final GroqProvider? groqProvider;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final SecureStorageService _storage;
  late final GroqProvider _groqProvider;

  bool _isLoading = true;
  String _maskedApiKey = 'Not configured';
  bool _hasApiKey = false;
  String _selectedModel = AiConfig.defaultModel;

  bool _isTestingConnection = false;
  String? _connectionStatusMessage;
  bool? _connectionSuccess;

  @override
  void initState() {
    super.initState();
    _storage = widget.secureStorage ?? SecureStorageService();
    _groqProvider = widget.groqProvider ?? GroqProvider(secureStorage: _storage);
    _loadSettings();
  }

  @override
  void dispose() {
    // Only close the provider we created ourselves; an injected one is owned
    // by the caller.
    if (widget.groqProvider == null) {
      _groqProvider.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final key = await _storage.getGroqApiKey();
    final model = await _storage.getSelectedModel();

    if (mounted) {
      setState(() {
        _hasApiKey = key != null && key.isNotEmpty;
        _maskedApiKey = SecureStorageService.maskApiKey(key);
        _selectedModel = (model != null &&
                model.isNotEmpty &&
                AiConfig.availableModels.contains(model))
            ? model
            : AiConfig.defaultModel;
        _isLoading = false;
      });
    }
  }

  Future<void> _showApiKeyDialog() async {
    final controller = TextEditingController();
    bool obscure = true;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Groq API Key'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Enter your Groq API key from console.groq.com. '
                    'The key will be encrypted and saved securely.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    obscureText: obscure,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'API Key',
                      hintText: 'gsk_...',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscure ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setDialogState(() {
                            obscure = !obscure;
                          });
                        },
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    if (controller.text.trim().isNotEmpty) {
                      Navigator.of(ctx).pop(true);
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved == true && controller.text.trim().isNotEmpty) {
      await _storage.saveGroqApiKey(controller.text.trim());
      await _loadSettings();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Groq API key saved securely.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _removeApiKey() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove API Key'),
        content: const Text(
          'Are you sure you want to remove your saved Groq API key? '
          'Kitten will not be able to respond to messages without a configured key.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _storage.deleteGroqApiKey();
      await _loadSettings();
      if (mounted) {
        setState(() {
          _connectionStatusMessage = null;
          _connectionSuccess = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Groq API key removed.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTestingConnection = true;
      _connectionStatusMessage = null;
      _connectionSuccess = null;
    });

    try {
      final success = await _groqProvider.checkConnection();
      if (mounted) {
        setState(() {
          _connectionSuccess = success;
          _connectionStatusMessage =
              'Connection successful! Groq is connected and ready.';
        });
      }
    } on AiException catch (e) {
      if (mounted) {
        setState(() {
          _connectionSuccess = false;
          _connectionStatusMessage = e.userFriendlyMessage;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _connectionSuccess = false;
          _connectionStatusMessage =
              'Connection test failed. Please verify your internet and API key.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTestingConnection = false;
        });
      }
    }
  }

  Future<void> _changeModel(String? newModel) async {
    if (newModel == null || newModel == _selectedModel) return;

    await _storage.saveSelectedModel(newModel);
    setState(() {
      _selectedModel = newModel;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                // ── AI & Groq Configuration ────────────────────
                _SectionHeader(
                  title: 'AI Provider & Brain',
                  colorScheme: cs,
                  textTheme: tt,
                ),

                ListTile(
                  leading: const Icon(Icons.smart_toy_outlined),
                  title: const Text('AI Provider'),
                  subtitle: const Text('Groq Cloud (OpenAI-compatible)'),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Active',
                      style: tt.labelSmall?.copyWith(
                        color: cs.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                ListTile(
                  leading: const Icon(Icons.psychology_outlined),
                  title: const Text('Model'),
                  subtitle: Text(_selectedModel),
                  trailing: DropdownButton<String>(
                    value: _selectedModel,
                    underline: const SizedBox(),
                    items: AiConfig.availableModels.map((model) {
                      return DropdownMenuItem(
                        value: model,
                        child: Text(
                          model,
                          style: const TextStyle(fontSize: 13),
                        ),
                      );
                    }).toList(),
                    onChanged: _changeModel,
                  ),
                ),

                ListTile(
                  leading: const Icon(Icons.key_outlined),
                  title: const Text('API Key'),
                  subtitle: Text(
                    _maskedApiKey,
                    style: TextStyle(
                      fontFamily: _hasApiKey ? 'monospace' : null,
                      color: _hasApiKey ? cs.onSurface : cs.error,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_hasApiKey)
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Remove Key',
                          onPressed: _removeApiKey,
                        ),
                      IconButton(
                        icon: Icon(_hasApiKey ? Icons.edit_outlined : Icons.add),
                        tooltip: _hasApiKey ? 'Change Key' : 'Add Key',
                        onPressed: _showApiKeyDialog,
                      ),
                    ],
                  ),
                ),

                // Connection Test Action
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: (_isTestingConnection || !_hasApiKey)
                              ? null
                              : _testConnection,
                          icon: _isTestingConnection
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.wifi_tethering),
                          label: Text(
                            _isTestingConnection
                                ? 'Testing Connection...'
                                : 'Test Connection',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Connection Feedback Banner
                if (_connectionStatusMessage != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _connectionSuccess == true
                            ? cs.primaryContainer.withAlpha(120)
                            : cs.errorContainer.withAlpha(120),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _connectionSuccess == true
                              ? cs.primary
                              : cs.error,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _connectionSuccess == true
                                ? Icons.check_circle_outline
                                : Icons.error_outline,
                            color: _connectionSuccess == true
                                ? cs.primary
                                : cs.error,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _connectionStatusMessage!,
                              style: tt.bodySmall?.copyWith(
                                color: _connectionSuccess == true
                                    ? cs.onPrimaryContainer
                                    : cs.onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                const Divider(height: 32),

                // ── Assistant (Placeholders for Future Tasks) ────
                _SectionHeader(
                  title: 'Assistant',
                  colorScheme: cs,
                  textTheme: tt,
                ),
                _PlaceholderTile(
                  icon: Icons.record_voice_over_outlined,
                  title: 'Wake Word',
                  subtitle: 'Not configured',
                ),
                _PlaceholderTile(
                  icon: Icons.graphic_eq,
                  title: 'Voice',
                  subtitle: 'Default',
                ),

                const Divider(height: 32),

                // ── Permissions (Placeholders) ─────────────────
                _SectionHeader(
                  title: 'Permissions',
                  colorScheme: cs,
                  textTheme: tt,
                ),
                _PlaceholderTile(
                  icon: Icons.mic_none,
                  title: 'Microphone',
                  subtitle: 'Not granted',
                ),
                _PlaceholderTile(
                  icon: Icons.screen_search_desktop_outlined,
                  title: 'Screen Understanding',
                  subtitle: 'Not granted',
                ),
                _PlaceholderTile(
                  icon: Icons.apps_outlined,
                  title: 'App Awareness',
                  subtitle: 'Not granted',
                ),

                const Divider(height: 32),

                // ── Appearance (Placeholders) ──────────────────
                _SectionHeader(
                  title: 'Appearance',
                  colorScheme: cs,
                  textTheme: tt,
                ),
                _PlaceholderTile(
                  icon: Icons.pets_outlined,
                  title: 'Kitten Appearance',
                  subtitle: 'Default',
                ),
                _PlaceholderTile(
                  icon: Icons.palette_outlined,
                  title: 'Theme',
                  subtitle: 'System default',
                ),

                const Divider(height: 32),

                // ── Privacy (Placeholders) ─────────────────────
                _SectionHeader(
                  title: 'Privacy',
                  colorScheme: cs,
                  textTheme: tt,
                ),
                _PlaceholderTile(
                  icon: Icons.security_outlined,
                  title: 'Data & Permissions',
                  subtitle: 'Manage your data',
                ),
                _PlaceholderTile(
                  icon: Icons.memory_outlined,
                  title: 'Memory',
                  subtitle: 'Not enabled',
                ),

                const SizedBox(height: 24),

                // ── Version info ────────────────────────────────
                Center(
                  child: Text(
                    'Kitten AI v1.0.0',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
    );
  }
}

// ── Private helper widgets ──────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.colorScheme,
    required this.textTheme,
  });

  final String title;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        title,
        style: textTheme.titleSmall?.copyWith(
          color: colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _PlaceholderTile extends StatelessWidget {
  const _PlaceholderTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$title will be available in a future update.'),
            duration: const Duration(seconds: 2),
          ),
        );
      },
    );
  }
}
