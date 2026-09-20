import 'dart:async';

import 'package:flutter/material.dart';

import 'package:kitten/core/ai/config/ai_config.dart';
import 'package:kitten/core/awareness/services/app_awareness_controller.dart';
import 'package:kitten/core/ai/models/ai_exception.dart';
import 'package:kitten/core/ai/providers/groq_provider.dart';
import 'package:kitten/core/services/secure_storage_service.dart';
import 'package:kitten/core/voice/config/voice_config.dart';
import 'package:kitten/core/voice/services/voice_controller.dart';

/// Settings screen for Kitten AI.
///
/// Features functional Groq AI configuration (API key management, model selection,
/// connection testing) alongside placeholder sections for future capabilities.
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    this.secureStorage,
    this.groqProvider,
    this.voiceController,
    this.awarenessController,
  });

  final SecureStorageService? secureStorage;
  final GroqProvider? groqProvider;

  /// The live voice session, when one exists, so voice switches take effect
  /// immediately instead of only after a restart.
  final VoiceController? voiceController;

  /// The live app-awareness session, for the same reason.
  final AppAwarenessController? awarenessController;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> with WidgetsBindingObserver {
  late final SecureStorageService _storage;
  late final GroqProvider _groqProvider;
  late final AppAwarenessController _awareness;

  bool _isLoading = true;
  String _maskedApiKey = 'Not configured';
  bool _hasApiKey = false;
  String _selectedModel = AiConfig.defaultModel;

  bool _isTestingConnection = false;
  String? _connectionStatusMessage;
  bool? _connectionSuccess;

  bool _wakeWordEnabled = VoiceConfig.wakeWordByDefault;
  bool _speakReplies = VoiceConfig.speakRepliesByDefault;

  /// True while the user has been sent to grant usage access, so returning to
  /// the app can finish what they started.
  bool _awaitingUsageAccess = false;

  @override
  void initState() {
    super.initState();
    _storage = widget.secureStorage ?? SecureStorageService();
    _groqProvider = widget.groqProvider ?? GroqProvider(secureStorage: _storage);
    _awareness = widget.awarenessController ?? AppAwarenessController();
    _awareness.addListener(_onAwarenessUpdate);
    WidgetsBinding.instance.addObserver(this);
    // Asks the platform about usage access and repaints when it answers, so
    // the rest of the screen never waits on it.
    unawaited(_awareness.refreshPermission());
    _loadSettings();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _awareness.removeListener(_onAwarenessUpdate);
    if (widget.awarenessController == null) {
      _awareness.dispose();
    }
    // Only close the provider we created ourselves; an injected one is owned
    // by the caller.
    if (widget.groqProvider == null) {
      _groqProvider.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // The user was sent to system settings to grant usage access; finish the
    // enable they asked for now that they are back.
    if (_awaitingUsageAccess && !_awareness.enabled) {
      unawaited(_finishUsageAccessGrant());
    }
  }

  void _onAwarenessUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _loadSettings() async {
    final key = await _storage.getGroqApiKey();
    final model = await _storage.getSelectedModel();
    final wakeWord = await _storage.getWakeWordEnabled();
    final speakReplies = await _storage.getSpeakReplies();

    if (mounted) {
      setState(() {
        _hasApiKey = key != null && key.isNotEmpty;
        _maskedApiKey = SecureStorageService.maskApiKey(key);
        _selectedModel = (model != null &&
                model.isNotEmpty &&
                AiConfig.availableModels.contains(model))
            ? model
            : AiConfig.defaultModel;
        _wakeWordEnabled = wakeWord ?? VoiceConfig.wakeWordByDefault;
        _speakReplies = speakReplies ?? VoiceConfig.speakRepliesByDefault;
        _isLoading = false;
      });
    }
  }

  Future<void> _changeWakeWord(bool enabled) async {
    setState(() {
      _wakeWordEnabled = enabled;
    });
    await _storage.saveWakeWordEnabled(enabled);

    if (enabled) {
      await widget.voiceController?.enableWakeWord();
    } else {
      await widget.voiceController?.disableWakeWord();
    }

    // The controller refuses to watch when speech is unavailable, so mirror its
    // real state back into the switch rather than lying to the user.
    final actual = widget.voiceController?.wakeWordEnabled ?? enabled;
    if (mounted && actual != enabled) {
      setState(() {
        _wakeWordEnabled = actual;
      });
      await _storage.saveWakeWordEnabled(actual);
    }
  }

  /// Describes the current state of app awareness in one line.
  String _appAwarenessSubtitle() {
    if (!_awareness.isSupported) {
      return 'Only available on Android';
    }
    if (!_awareness.hasUsageAccess) {
      return 'Off — grant Usage access below to let Kitten see the app you use';
    }
    if (_awareness.enabled) {
      return 'On — Kitten knows which app you were last using';
    }
    return 'Off — Kitten cannot see which app you use';
  }

  Future<void> _openUsageAccessSettings() async {
    await _awareness.openUsageAccessSettings();
    if (mounted) {
      setState(() => _awaitingUsageAccess = true);
    }
  }

  Future<void> _finishUsageAccessGrant() async {
    final enabled = await _awareness.enable(openSettingsIfMissing: false);
    if (!mounted) return;

    setState(() {
      _awaitingUsageAccess = !enabled;
    });

    if (enabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Usage access granted. Kitten can see the app you use.'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _changeAppAwareness(bool enabled) async {
    if (!enabled) {
      await _awareness.disable();
      if (mounted) setState(() => _awaitingUsageAccess = false);
      return;
    }

    final ok = await _awareness.enable();
    if (!mounted) return;

    setState(() {
      // enable() opens system settings when the permission is missing, so
      // remember to finish the job when the user comes back.
      _awaitingUsageAccess = !ok;
    });

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _awareness.lastError ?? 'App awareness could not be enabled.',
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _changeSpeakReplies(bool enabled) async {
    setState(() {
      _speakReplies = enabled;
    });
    await _storage.saveSpeakReplies(enabled);
    widget.voiceController?.setSpeakReplies(enabled);
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
                SwitchListTile(
                  secondary: const Icon(Icons.record_voice_over_outlined),
                  title: const Text('Wake Word'),
                  subtitle: Text(
                    _wakeWordEnabled
                        ? 'Waiting for "${VoiceConfig.wakePhrases.first}" — '
                            'listening while the app is open'
                        : 'Off — enable to wake Kitten by voice',
                  ),
                  value: _wakeWordEnabled,
                  onChanged: _changeWakeWord,
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.graphic_eq),
                  title: const Text('Speak Replies'),
                  subtitle: Text(
                    _speakReplies
                        ? 'Kitten reads its answers aloud'
                        : 'Kitten stays silent',
                  ),
                  value: _speakReplies,
                  onChanged: _changeSpeakReplies,
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.apps_outlined),
                  title: const Text('App Awareness'),
                  subtitle: Text(_appAwarenessSubtitle()),
                  value: _awareness.enabled,
                  onChanged: _changeAppAwareness,
                ),
                if (_awareness.currentApp != null)
                  ListTile(
                    leading: const Icon(Icons.visibility_outlined),
                    title: const Text('Last app seen'),
                    subtitle: Text(
                      '${_awareness.currentApp!.displayName}  '
                      '(${_awareness.currentApp!.packageName})',
                    ),
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
                ListTile(
                  leading: const Icon(Icons.query_stats_outlined),
                  title: const Text('Usage Access'),
                  subtitle: Text(
                    !_awareness.isSupported
                        ? 'Only available on Android'
                        : (_awareness.hasUsageAccess
                            ? 'Granted'
                            : 'Not granted'),
                  ),
                  trailing: _awareness.isSupported &&
                          !_awareness.hasUsageAccess
                      ? TextButton(
                          onPressed: _openUsageAccessSettings,
                          child: const Text('Grant'),
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: _awareness.isSupported
                      ? _openUsageAccessSettings
                      : null,
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
