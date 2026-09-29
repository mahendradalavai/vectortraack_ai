import 'package:kitten/core/tools/kitten_tool.dart';

/// The set of tools Kitten is allowed to use.
///
/// A registry rather than a fixed list so Task 010 and 011 can add phone
/// actions without touching the conversation loop: register a tool, and the
/// loop, the prompt, and the request payload all pick it up.
class ToolRegistry {
  final Map<String, KittenTool> _tools = {};

  /// Registers a tool, replacing any earlier tool of the same name.
  void register(KittenTool tool) => _tools[tool.name] = tool;

  /// Registers several tools at once.
  void registerAll(Iterable<KittenTool> tools) {
    for (final tool in tools) {
      register(tool);
    }
  }

  /// Removes a tool by name.
  void unregister(String name) => _tools.remove(name);

  /// The tool with this name, or null when it is not registered.
  KittenTool? byName(String name) => _tools[name];

  /// Every registered tool, in registration order.
  List<KittenTool> get all => List.unmodifiable(_tools.values);

  bool get isEmpty => _tools.isEmpty;
  bool get isNotEmpty => _tools.isNotEmpty;
  int get length => _tools.length;

  /// The OpenAI-compatible `tools` array for a chat request.
  List<Map<String, dynamic>> toRequestJson() => [
        for (final tool in _tools.values)
          {
            'type': 'function',
            'function': {
              'name': tool.name,
              'description': tool.description,
              'parameters': tool.parametersSchema,
            },
          },
      ];
}
