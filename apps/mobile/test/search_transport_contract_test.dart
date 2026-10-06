import 'package:flutter_test/flutter_test.dart';
import 'package:pulsemesh/features/search/search_models.dart';
import 'package:pulsemesh/features/search/search_transport.dart';

class FakeSearchTransport implements SearchTransport {
  @override
  Future<SearchResults> search(String query, {int limit = 20}) async {
    return const SearchResults(messages: [], users: [], channels: []);
  }

  @override
  Future<String> startDirectConversation(String userId) async {
    return 'conversation-$userId';
  }
}

void main() {
  test('search transport can resolve a direct conversation id', () async {
    final transport = FakeSearchTransport();

    expect(
      await transport.startDirectConversation('user-1'),
      'conversation-user-1',
    );
  });
}
