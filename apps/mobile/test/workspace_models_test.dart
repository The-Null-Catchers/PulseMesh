import 'package:flutter_test/flutter_test.dart';
import 'package:pulsemesh/features/workspaces/workspace_models.dart';

void main() {
  test('parses workspace summaries from the API contract', () {
    final workspace = WorkspaceSummary.fromJson({
      'id': 'workspace-1',
      'name': 'The Null Catchers',
      'slug': 'the-null-catchers',
      'avatar_url': null,
      'description': 'Core team workspace',
      'role': 'Owner',
    });

    expect(workspace.id, 'workspace-1');
    expect(workspace.name, 'The Null Catchers');
    expect(workspace.role, 'Owner');
    expect(workspace.description, 'Core team workspace');
  });
}
