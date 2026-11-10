import 'dart:convert';
import 'dart:typed_data';

/// One tool the MCP server offers an agent: its schema, what it promises
/// ([readOnly]) and the handler that runs it.
///
/// Handlers report a problem the agent can fix (a bad argument, no device) by
/// throwing [McpToolError]; the server turns that into an `isError` result.
/// Anything else thrown is a bug and is reported as an internal error.
class const McpTool({
  required final String name,
  required final String title,
  required final String description,

  /// JSON Schema for the arguments: an object schema.
  required final Map<String, Object?> inputSchema,
  required final Future<McpToolResult> Function(McpArguments arguments) handler,

  /// Whether the tool leaves devices, apps and the user's Eagly state as they
  /// were. Every phase-1 tool is read-only (docs/MCP_SERVER.md §4.2).
  final bool readOnly = true,

  /// Whether calling it twice with the same arguments does nothing more.
  final bool idempotent = true,
}) {
  /// The tool as `tools/list` describes it.
  Map<String, Object?> toJson() => {
    'name': name,
    'title': title,
    'description': description,
    'inputSchema': inputSchema,
    'annotations': {
      'title': title,
      'readOnlyHint': readOnly,
      'destructiveHint': false,
      'idempotentHint': idempotent,
      'openWorldHint': false,
    },
  };
}

/// What a tool returns: structured JSON (also sent as text for clients that
/// don't read `structuredContent`), and optionally an image.
class const McpToolResult({
  final Map<String, Object?>? structured,
  final String? text,
  final McpImage? image,
  final bool isError = false,
}) {
  factory McpToolResult.json(Map<String, Object?> value) =>
      McpToolResult(structured: value);

  factory McpToolResult.error(String message) =>
      McpToolResult(text: message, isError: true);

  Map<String, Object?> toJson() => {
    'content': [
      if (image case final image?)
        {
          'type': 'image',
          'data': base64Encode(image.bytes),
          'mimeType': image.mimeType,
        },
      if (text case final text?) {'type': 'text', 'text': text},
      if (structured case final structured? when text == null)
        {'type': 'text', 'text': jsonEncode(structured)},
    ],
    'structuredContent': ?structured,
    'isError': isError,
  };
}

class const McpImage(
  final Uint8List bytes, {
  final String mimeType = 'image/png',
});

/// A problem with a tool call that the agent can act on: the message says
/// what was wrong and, where it can, what to do instead.
class const McpToolError(final String message) implements Exception {
  @override
  String toString() => message;
}

/// A tool call's `arguments`, with typed getters that throw [McpToolError]
/// naming the argument when a value has the wrong type or range.
class McpArguments(final Map<String, Object?> values) {
  String? string(String name) {
    final value = values[name];
    if (value == null) return null;
    if (value is! String) throw McpToolError('"$name" must be a string.');
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String requiredString(String name) =>
      string(name) ?? (throw McpToolError('"$name" is required.'));

  int? integer(String name, {int? min, int? max}) {
    final value = values[name];
    if (value == null) return null;
    final number = switch (value) {
      int() => value,
      double() when value == value.roundToDouble() => value.toInt(),
      String() => int.tryParse(value.trim()),
      _ => null,
    };
    if (number == null) throw McpToolError('"$name" must be an integer.');
    if (min != null && number < min) {
      throw McpToolError('"$name" must be at least $min.');
    }
    if (max != null && number > max) {
      throw McpToolError('"$name" must be at most $max.');
    }
    return number;
  }

  bool? boolean(String name) {
    final value = values[name];
    if (value == null) return null;
    if (value is bool) return value;
    if (value == 'true') return true;
    if (value == 'false') return false;
    throw McpToolError('"$name" must be true or false.');
  }

  List<String>? strings(String name) {
    final value = values[name];
    if (value == null) return null;
    if (value is String) return [value];
    if (value is List && value.every((item) => item is String)) {
      return value.cast<String>();
    }
    throw McpToolError('"$name" must be a list of strings.');
  }
}

// ── Schema helpers ──────────────────────────────────────────────────────

/// An object schema with [properties], none required unless named.
Map<String, Object?> objectSchema(
  Map<String, Map<String, Object?>> properties, {
  List<String> required = const [],
}) => {
  'type': 'object',
  'properties': properties,
  if (required.isNotEmpty) 'required': required,
  'additionalProperties': false,
};

Map<String, Object?> stringProperty(
  String description, {
  List<String>? enumValues,
}) => {'type': 'string', 'description': description, 'enum': ?enumValues};

Map<String, Object?> integerProperty(
  String description, {
  int? minimum,
  int? maximum,
  int? defaultValue,
}) => {
  'type': 'integer',
  'description': description,
  'minimum': ?minimum,
  'maximum': ?maximum,
  'default': ?defaultValue,
};

Map<String, Object?> booleanProperty(
  String description, {
  bool? defaultValue,
}) => {'type': 'boolean', 'description': description, 'default': ?defaultValue};

Map<String, Object?> stringListProperty(
  String description, {
  List<String>? enumValues,
}) => {
  'type': 'array',
  'description': description,
  'items': {'type': 'string', 'enum': ?enumValues},
};
