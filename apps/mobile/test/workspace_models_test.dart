import 'package:flutter_test/flutter_test.dart';
import 'package:pulsemesh/features/workspaces/workspace_models.dart';

void main() {
  test('parses and serializes workspace summaries', () {
    final workspace = WorkspaceSummary.fromJson({
      'id': 'workspace-1',
      'name': 'The Null Catchers',
      'slug': 'the-null-catchers',
      'avatar_url': null,
      'description': 'Realtime engineering workspace',
      'role': 'Owner',
    });

    expect(workspace.name, 'The Null Catchers');
    expect(workspace.role, 'Owner');
    expect(workspace.toJson()['slug'], 'the-null-catchers');
  });
}
