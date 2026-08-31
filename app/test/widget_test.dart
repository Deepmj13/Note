import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_v4/main.dart';
import 'package:note_v4/providers/auth_notifier.dart';
import 'package:note_v4/ui/screens/login_screen.dart';

class _SignedOutAuthController extends AuthController {
  @override
  AuthUser? build() => null;

  @override
  Future<void> signInWithEmail(String email, String password) async {}

  @override
  Future<void> signUpWithEmail(String email, String password) async {}

  @override
  Future<void> signOut() async {}
}

class _ReadyAuthReady extends AuthReady {
  @override
  bool build() => true;
}

void main() {
  testWidgets('shows login screen when signed out', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authReadyProvider.overrideWith(_ReadyAuthReady.new),
          authControllerProvider.overrideWith(_SignedOutAuthController.new),
        ],
        child: const NoteApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
