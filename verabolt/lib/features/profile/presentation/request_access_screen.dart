import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:verabolt/core/utils/device_anchor.dart';
import 'package:verabolt/core/utils/friendly_error.dart';
import 'package:verabolt/core/utils/connectivity_provider.dart';
import 'package:verabolt/core/widgets/overlay_message.dart';
import 'package:verabolt/core/widgets/primary_button.dart';
import 'package:verabolt/features/auth/application/auth_providers.dart';
import 'package:verabolt/features/profile/application/profile_providers.dart';

class RequestAccessScreen extends ConsumerStatefulWidget {
  const RequestAccessScreen({super.key});

  @override
  ConsumerState<RequestAccessScreen> createState() => _RequestAccessScreenState();
}

class _RequestAccessScreenState extends ConsumerState<RequestAccessScreen> {
  bool _loading = false;
  String? _error;
  String? _deviceId;
  bool _requested = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final id = await DeviceAnchor.get();
      if (!mounted) return;
      setState(() => _deviceId = id);
    });
  }

  Future<void> _requestAccess() async {
    final offline = ref.read(isOfflineProvider);
    if (offline) {
      const msg = 'You\'re offline. Connect to the internet to request access.';
      setState(() {
        _loading = false;
        _error = msg;
        _requested = false;
      });
      if (mounted) {
        await OverlayMessage.error(context, msg);
      }
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _requested = false;
    });

    try {
      final user = await ref.read(authUserProvider.future);
      if (user == null) {
        if (!mounted) return;
        context.go('/login');
        return;
      }

      final deviceId = await DeviceAnchor.get();
      await ref.read(profileRepositoryProvider).requestAccess(
            userId: user.id,
            deviceId: deviceId,
          );

      ref.invalidate(profileStatusProvider);

      if (!mounted) return;
      setState(() => _requested = true);
      await OverlayMessage.success(
        context,
        'Request sent. Waiting for admin approval.',
      );
      context.go('/waiting-approval');
    } catch (e) {
      final msg = friendlyError(e);
      setState(() => _error = msg);
      if (mounted) {
        await OverlayMessage.error(context, msg);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
     appBar: AppBar(
  leading: IconButton(
    icon: const Icon(Icons.arrow_back_rounded),
    tooltip: 'Back to dashboard',
    onPressed: () => context.go('/dashboard'),
  ),
  title: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      // Small logo — looks premium next to title
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.asset(
          'lib/images/verabolt.png',
          height: 28,
          width: 28,
          fit: BoxFit.contain,
        ),
      ),
      const SizedBox(width: 12),
      Text(
        'Request Access',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
      ),
    ],
  ),
  centerTitle: false, // left-aligned looks better with logo + back icon
  elevation: 0,       // flat modern look (or 1-2 if you want subtle shadow)
  actions: [
    IconButton(
      icon: const Icon(Icons.logout_rounded),
      tooltip: 'Sign out',
      onPressed: () async {
        if (context.mounted) context.go('/login');
        Future.microtask(() async {
          await ref.read(authRepositoryProvider).signOut();
        });
      },
    ),
  ],
),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.surface,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        Icons.verified_user_outlined,
                        size: 44,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Request Professional Access',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Send your device anchor to an admin for approval. Once approved, your assigned license key will appear on the Activation screen.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Device anchor ID',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: SelectableText(
                          _deviceId ?? '...',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (_requested)
                        Text(
                          'Request sent successfully. Please wait for admin approval.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Theme.of(context).colorScheme.primary),
                        ),
                      const SizedBox(height: 14),
                      PrimaryButton(
                        label: _requested ? 'Request sent' : 'Send request',
                        onPressed: (_loading || _requested) ? null : _requestAccess,
                        loading: _loading,
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton(
                        onPressed: _loading
                            ? null
                            : () {
                                context.go('/waiting-approval');
                              },
                        child: const Text('I already requested access'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
