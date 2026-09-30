import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../theme/app_theme.dart';
import 'auth_models.dart';
import 'auth_session_controller.dart';
import 'auth_session_store.dart';
import 'auth_transport.dart';

typedef AuthenticatedAppBuilder = Widget Function();

class AuthSessionScope extends InheritedWidget {
  const AuthSessionScope({
    required this.controller,
    required super.child,
    super.key,
  });

  final AuthSessionController controller;

  static AuthSessionController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AuthSessionScope>();
    assert(scope != null, 'AuthSessionScope is missing above this context');
    return scope!.controller;
  }

  @override
  bool updateShouldNotify(AuthSessionScope oldWidget) {
    return controller != oldWidget.controller;
  }
}

class MobileAuthBootstrap extends StatefulWidget {
  const MobileAuthBootstrap({
    required this.authenticatedAppBuilder,
    this.controller,
    this.config = AppConfig.fromEnvironment,
    super.key,
  });

  final AuthenticatedAppBuilder authenticatedAppBuilder;
  final AuthSessionController? controller;
  final AppConfig config;

  @override
  State<MobileAuthBootstrap> createState() => _MobileAuthBootstrapState();
}

class _MobileAuthBootstrapState extends State<MobileAuthBootstrap> {
  late final AuthSessionController _controller;
  bool _restoring = true;
  bool _authenticated = false;
  Object? _restoreError;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ??
        AuthSessionController(
          transport: DioAuthTransport(baseUrl: widget.config.apiBaseUrl),
          store: SecureAuthSessionStore(),
        );
    _restore();
  }

  Future<void> _restore() async {
    if (mounted) {
      setState(() {
        _restoring = true;
        _restoreError = null;
      });
    }

    try {
      final authenticated = await _controller.restore();
      if (!mounted) return;
      setState(() {
        _authenticated = authenticated;
        _restoring = false;
      });
    } on AuthTransportException catch (error) {
      if (!mounted) return;

      if (error.isUnauthorized) {
        setState(() {
          _authenticated = false;
          _restoring = false;
          _restoreError = null;
        });
        return;
      }

      setState(() {
        _authenticated = false;
        _restoring = false;
        _restoreError = error;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _authenticated = false;
        _restoring = false;
        _restoreError = error;
      });
    }
  }

  void _onAuthenticated() {
    setState(() {
      _authenticated = true;
      _restoreError = null;
    });
  }

  void _showSignIn() {
    setState(() {
      _authenticated = false;
      _restoring = false;
      _restoreError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_authenticated) {
      return AuthSessionScope(
        controller: _controller,
        child: widget.authenticatedAppBuilder(),
      );
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PulseMesh',
      theme: buildPulseMeshTheme(),
      home: _restoring
          ? const _AuthLoadingScreen()
          : _restoreError != null
              ? _RestoreErrorScreen(
                  onRetry: _restore,
                  onSignIn: _showSignIn,
                )
              : AuthScreen(
                  controller: _controller,
                  onAuthenticated: _onAuthenticated,
                ),
    );
  }
}

class _AuthLoadingScreen extends StatelessWidget {
  const _AuthLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: SizedBox.square(
          dimension: 36,
          child: CircularProgressIndicator(),
        ),
      ),
    );
  }
}

class _RestoreErrorScreen extends StatelessWidget {
  const _RestoreErrorScreen({
    required this.onRetry,
    required this.onSignIn,
  });

  final VoidCallback onRetry;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        minimum: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_rounded, size: 52),
                const SizedBox(height: 18),
                Text(
                  'Could not restore your session',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Your saved session is still secure. Check your connection and try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white60, height: 1.4),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try again'),
                ),
                TextButton(
                  onPressed: onSignIn,
                  child: const Text('Sign in instead'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    required this.controller,
    required this.onAuthenticated,
    super.key,
  });

  final AuthSessionController controller;
  final VoidCallback onAuthenticated;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _username = TextEditingController();
  final _displayName = TextEditingController();

  bool _register = false;
  bool _submitting = false;
  bool _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _username.dispose();
    _displayName.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      if (_register) {
        await widget.controller.register(
          RegisterCredentials(
            email: _email.text.trim(),
            password: _password.text,
            username: _username.text.trim(),
            displayName: _displayName.text.trim(),
            device: 'PulseMesh Mobile',
          ),
        );
      } else {
        await widget.controller.login(
          LoginCredentials(
            email: _email.text.trim(),
            password: _password.text,
            device: 'PulseMesh Mobile',
          ),
        );
      }

      if (!mounted) return;
      widget.onAuthenticated();
    } on AuthTransportException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not reach PulseMesh. Try again.');
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  void _toggleMode() {
    setState(() {
      _register = !_register;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = _register ? 'Create your account' : 'Welcome back';
    final subtitle = _register
        ? 'Join your team on PulseMesh.'
        : 'Sign in to continue to your workspace.';

    return Scaffold(
      body: SafeArea(
        minimum: const EdgeInsets.all(24),
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _PulseMeshMark(),
                    const SizedBox(height: 32),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.white60,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 28),
                    if (_register) ...[
                      TextFormField(
                        key: const Key('auth-display-name'),
                        controller: _displayName,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Display name',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                        validator: (value) => (value?.trim().isEmpty ?? true)
                            ? 'Display name is required'
                            : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        key: const Key('auth-username'),
                        controller: _username,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Username',
                          prefixIcon: Icon(Icons.alternate_email_rounded),
                        ),
                        validator: (value) {
                          final username = value?.trim() ?? '';
                          if (username.length < 3) {
                            return 'Username must be at least 3 characters';
                          }
                          if (!RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(username)) {
                            return 'Use letters, numbers, dots, dashes or underscores';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                    ],
                    TextFormField(
                      key: const Key('auth-email'),
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.mail_outline_rounded),
                      ),
                      validator: (value) {
                        final email = value?.trim() ?? '';
                        if (!email.contains('@') || !email.contains('.')) {
                          return 'Enter a valid email address';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      key: const Key('auth-password'),
                      controller: _password,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      autofillHints: _register
                          ? const [AutofillHints.newPassword]
                          : const [AutofillHints.password],
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          onPressed: () {
                            setState(
                              () => _obscurePassword = !_obscurePassword,
                            );
                          },
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_rounded
                                : Icons.visibility_off_rounded,
                          ),
                        ),
                      ),
                      validator: (value) => (value?.length ?? 0) < 12
                          ? 'Password must be at least 12 characters'
                          : null,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .errorContainer
                              .withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    FilledButton(
                      key: const Key('auth-submit'),
                      onPressed: _submitting ? null : _submit,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: _submitting
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(_register ? 'Create account' : 'Sign in'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      key: const Key('auth-toggle-mode'),
                      onPressed: _submitting ? null : _toggleMode,
                      child: Text(
                        _register
                            ? 'Already have an account? Sign in'
                            : 'New to PulseMesh? Create an account',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PulseMeshMark extends StatelessWidget {
  const _PulseMeshMark();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: const Color(0xFF68E0CF),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.hub_rounded,
            color: Color(0xFF071015),
          ),
        ),
        const SizedBox(width: 12),
        const Text(
          'PulseMesh',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
          ),
        ),
      ],
    );
  }
}
