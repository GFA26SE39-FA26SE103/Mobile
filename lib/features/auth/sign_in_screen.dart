import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets.dart';
import 'auth_controller.dart';
import 'auth_models.dart';

class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key, this.tagline = 'Secure access for on-shift staff'});
  final String tagline;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: c.primary, borderRadius: BorderRadius.circular(12)),
          child: Text('SO', style: TextStyle(color: c.onPrimary, fontWeight: FontWeight.w800, fontSize: 15)),
        ),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('SUPERMARKET OPS', style: TextStyle(color: c.text, fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: 0.4)),
          Text('Staff mobile', style: TextStyle(color: c.textMuted, fontSize: 12.5, fontWeight: FontWeight.w500)),
        ]),
      ]),
      const SizedBox(height: 10),
      Text(tagline, style: TextStyle(color: c.textMuted, fontSize: 12.5)),
    ]);
  }
}

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key, this.initialEmail});
  final String? initialEmail;

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _form = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.initialEmail ?? '');
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _remember = true;
  bool _obscure = true;
  SignInStage? _stage;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _stage = SignInStage.credentials;
    });
    try {
      await ref.read(authControllerProvider.notifier).signIn(
            email: _email.text,
            password: _password.text,
            remember: _remember,
            onStage: (stage) {
              if (mounted) setState(() => _stage = stage);
            },
          );
    } on SignInFailure catch (e) {
      if (mounted) {
        setState(() {
          _stage = null;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final busy = _stage != null;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          children: [
            const BrandHeader(),
            const SizedBox(height: 40),
            if (busy) _SigningIn(stage: _stage!) else _buildForm(context, c),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context, AppColors c) {
    final theme = Theme.of(context).textTheme;
    return Form(
      key: _form,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Welcome back', style: theme.headlineSmall),
        const SizedBox(height: 8),
        Text('Sign in with your staff account to see your tasks and task offers for your zone.',
            style: theme.bodyMedium?.copyWith(color: c.textMuted)),
        const SizedBox(height: 24),
        if (_error != null) ...[
          InfoBanner(tone: BannerTone.danger, icon: Icons.error_outline, title: _error!),
          const SizedBox(height: 16),
        ],
        const _Label('Email'),
        TextFormField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.username, AutofillHints.email],
          textInputAction: TextInputAction.next,
          autocorrect: false,
          decoration: const InputDecoration(hintText: 'linh.nguyen@store.com'),
          validator: (v) {
            final value = (v ?? '').trim();
            if (value.isEmpty) return 'Enter your work email.';
            if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)) return 'Enter a valid email address.';
            return null;
          },
          onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
        ),
        const SizedBox(height: 16),
        const _Label('Password'),
        TextFormField(
          controller: _password,
          focusNode: _passwordFocus,
          obscureText: _obscure,
          autofillHints: const [AutofillHints.password],
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            suffixIcon: TextButton(
              onPressed: () => setState(() => _obscure = !_obscure),
              child: Text(_obscure ? 'Show' : 'Hide'),
            ),
          ),
          validator: (v) => (v ?? '').isEmpty ? 'Enter your password.' : null,
          onFieldSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 6),
        Row(children: [
          Checkbox(value: _remember, onChanged: (v) => setState(() => _remember = v ?? false)),
          GestureDetector(
            onTap: () => setState(() => _remember = !_remember),
            child: Text('Keep me signed in', style: TextStyle(color: c.textMuted, fontSize: 13.5)),
          ),
        ]),
        const SizedBox(height: 14),
        FilledButton(onPressed: _submit, child: const Text('Sign in')),
        const SizedBox(height: 18),
        Text('Forgot your password or locked out? Ask your shift manager to reset it.',
            textAlign: TextAlign.center, style: theme.bodySmall),
        if (AppConfig.mockAuth) ...[
          const SizedBox(height: 18),
          InfoBanner(
            tone: BannerTone.brand,
            icon: Icons.science_outlined,
            title: 'Demo sign-in',
            body: 'Any email with password ${'staff123'}. An email containing "manager" shows the wrong-role message.',
          ),
        ],
      ]),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
      );
}

class _SigningIn extends StatelessWidget {
  const _SigningIn({required this.stage});
  final SignInStage stage;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = Theme.of(context).textTheme;
    const steps = [
      (SignInStage.credentials, 'Checking credentials', 'Confirming your account'),
      (SignInStage.permissions, 'Loading staff permissions', 'Making sure this is a staff account'),
      (SignInStage.session, 'Starting secure session', 'Connecting to your zone'),
    ];
    return Semantics(
      liveRegion: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Signing in…', style: theme.headlineSmall),
        const SizedBox(height: 8),
        Text('Checking your account and loading your store access.', style: theme.bodyMedium?.copyWith(color: c.textMuted)),
        const SizedBox(height: 24),
        AppCard(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
          child: Column(children: [
            for (final (s, title, body) in steps)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(children: [
                  _StepMark(state: s.index < stage.index ? 1 : (s == stage ? 0 : -1)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title,
                          style: TextStyle(fontWeight: FontWeight.w600, color: s.index > stage.index ? c.textMuted : c.text)),
                      Text(body, style: theme.bodySmall),
                    ]),
                  ),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }
}

/// 1 = done, 0 = running, -1 = waiting.
class _StepMark extends StatelessWidget {
  const _StepMark({required this.state});
  final int state;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      width: 28,
      height: 28,
      child: switch (state) {
        1 => DecoratedBox(
            decoration: BoxDecoration(color: c.successTint, shape: BoxShape.circle),
            child: Icon(Icons.check, size: 16, color: c.success),
          ),
        0 => Padding(padding: const EdgeInsets.all(4), child: CircularProgressIndicator(strokeWidth: 2.5, color: c.primary)),
        _ => DecoratedBox(
            decoration: BoxDecoration(color: c.surface2, shape: BoxShape.circle, border: Border.all(color: c.border)),
          ),
      },
    );
  }
}

class SessionExpiredScreen extends ConsumerWidget {
  const SessionExpiredScreen({super.key, required this.user, required this.onSignInAgain, required this.onSwitchAccount});
  final AuthUser user;
  final VoidCallback onSignInAgain;
  final VoidCallback onSwitchAccount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final theme = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(24, 28, 24, 24), children: [
          const BrandHeader(tagline: 'Session protection'),
          const SizedBox(height: 40),
          Align(alignment: Alignment.centerLeft, child: Pill(label: 'SESSION ENDED', fg: c.warning, bg: c.warningTint, dot: true)),
          const SizedBox(height: 14),
          Text('Session expired', style: theme.headlineSmall),
          const SizedBox(height: 8),
          Text('Your session ended. Sign in again to keep receiving alerts for your zone.',
              style: theme.bodyMedium?.copyWith(color: c.textMuted)),
          const SizedBox(height: 22),
          AppCard(
            child: Row(children: [
              Avatar(user.initials, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(user.fullName.isEmpty ? user.email : user.fullName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  Text(user.email, style: theme.bodySmall),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: onSignInAgain, child: const Text('Sign in again')),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onSwitchAccount, child: const Text('Switch account')),
          const SizedBox(height: 18),
          Text('For your security, sessions end automatically.', textAlign: TextAlign.center, style: theme.bodySmall),
        ]),
      ),
    );
  }
}
