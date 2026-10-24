import 'layout_snapshot.dart';

/// One way to find a node again from a test: a label for the menu and the
/// text to copy.
class const LayoutSelector({
  required final String label,
  required final String value,
});

/// The selectors worth copying for [node], best first. Each picks the
/// node's most stable handle: its resource id (or a React Native `testID` /
/// Compose `testTag`, which arrive as one), then its text, then its content
/// description. XPath falls back to the node's position, and says which
/// match it is when the handle isn't unique in [snapshot].
List<LayoutSelector> selectorsFor(LayoutNode node, LayoutSnapshot snapshot) {
  final id = node.resourceId;
  final text = node.text;
  final description = node.contentDescription;
  // An Android resource id has a type; a bare one is a testID or testTag.
  final isResource = id != null && id.contains(':id/');

  return [
    if (id != null) LayoutSelector(label: 'Resource id', value: id),
    if (text != null) LayoutSelector(label: 'Text', value: text),
    if (description != null)
      LayoutSelector(label: 'Content description', value: description),
    LayoutSelector(label: 'XPath', value: xpathFor(node, snapshot)),
    if (id != null)
      LayoutSelector(label: 'UiAutomator', value: 'By.res(${_quoted(id)})')
    else if (text != null)
      LayoutSelector(label: 'UiAutomator', value: 'By.text(${_quoted(text)})')
    else if (description != null)
      LayoutSelector(
        label: 'UiAutomator',
        value: 'By.desc(${_quoted(description)})',
      ),
    if (isResource)
      LayoutSelector(
        label: 'Espresso',
        value: 'onView(withId(R.id.${node.resourceEntry}))',
      )
    else if (text != null)
      LayoutSelector(
        label: 'Espresso',
        value: 'onView(withText(${_quoted(text)}))',
      ),
    if (id != null && !isResource)
      LayoutSelector(
        label: 'Compose test',
        value: 'composeTestRule.onNodeWithTag(${_quoted(id)})',
      ),
    if (id != null)
      LayoutSelector(label: 'Maestro', value: 'id: ${_quoted(id)}')
    else if (text != null)
      LayoutSelector(label: 'Maestro', value: 'text: ${_quoted(text)}')
    else if (description != null)
      LayoutSelector(label: 'Maestro', value: 'text: ${_quoted(description)}'),
  ];
}

/// An XPath in the form Appium and `uiautomator dump` use: elements named
/// by class, attributes `resource-id`, `text` and `content-desc`.
String xpathFor(LayoutNode node, LayoutSnapshot snapshot) {
  for (final (attribute, value) in [
    ('resource-id', node.resourceId),
    ('text', node.text),
    ('content-desc', node.contentDescription),
  ]) {
    if (value == null) continue;
    final element = attribute == 'resource-id' ? '*' : node.className;
    final query = '//$element[@$attribute=${_xpathString(value)}]';
    final matches = [
      for (final each in snapshot.nodes)
        if (_attribute(each, attribute) == value &&
            (element == '*' || each.className == node.className))
          each,
    ];
    if (matches.length == 1) return query;
    final index = matches.indexOf(node);
    if (index >= 0) return '($query)[${index + 1}]';
  }
  // No handle: the path from the root, by class and 1-based position among
  // same-class siblings.
  final steps = <String>[];
  for (final each in node.ancestorsAndSelf) {
    final siblings = each.parent?.children ?? [each];
    final sameClass = siblings
        .where((sibling) => sibling.className == each.className)
        .toList();
    steps.add(
      sameClass.length == 1
          ? each.className
          : '${each.className}[${sameClass.indexOf(each) + 1}]',
    );
  }
  return '/hierarchy/${steps.join('/')}';
}

String? _attribute(LayoutNode node, String attribute) => switch (attribute) {
  'resource-id' => node.resourceId,
  'text' => node.text,
  _ => node.contentDescription,
};

/// XPath 1.0 has no escapes: a value with both quote kinds is concat()ed.
String _xpathString(String value) {
  if (!value.contains('"')) return '"$value"';
  if (!value.contains("'")) return "'$value'";
  final parts = value.split('"').map((part) => '"$part"').join(", '\"', ");
  return 'concat($parts)';
}

/// A double-quoted string literal; Java and YAML escape the same way here.
String _quoted(String value) =>
    '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll('\n', r'\n')}"';
