import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:verabolt/core/utils/device_id.dart';
import 'package:verabolt/core/utils/friendly_error.dart';
import 'package:verabolt/core/utils/connectivity_provider.dart';
import 'package:verabolt/core/widgets/app_text_field.dart';
import 'package:verabolt/core/widgets/overlay_message.dart';
import 'package:verabolt/core/widgets/primary_button.dart';
import 'package:verabolt/features/auth/application/auth_providers.dart';
import 'package:verabolt/features/licensing/application/license_info_provider.dart';
import 'package:verabolt/features/licensing/application/pro_status_provider.dart';
import 'package:verabolt/features/profile/application/profile_providers.dart';

class ActivationScreen extends ConsumerStatefulWidget {
  const ActivationScreen({super.key});

  @override
  ConsumerState<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends ConsumerState<ActivationScreen> {
  final _key = TextEditingController();

  bool _loading = false;
  String? _error;
  String? _deviceId;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final offline = ref.read(isOfflineProvider);
    if (offline) {
      const msg = 'You\'re offline. Connect to the internet to refresh license status.';
      if (!mounted) return;
      await OverlayMessage.error(context, msg);
      return;
    }

    ref.invalidate(licenseInfoProvider);
    ref.invalidate(isProProvider);
    ref.invalidate(profileStatusProvider);
    if (!mounted) return;
    await OverlayMessage.info(context, 'Refreshing license status...');
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final id = await DeviceId.get();
      if (!mounted) return;
      setState(() => _deviceId = id);
    });
  }

  Future<void> _activate() async {
    final offline = ref.read(isOfflineProvider);
    if (offline) {
      const msg = 'You\'re offline. Connect to the internet to activate your license.';
      setState(() {
        _loading = false;
        _error = msg;
      });
      if (mounted) {
        await OverlayMessage.error(context, msg);
      }
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = await ref.read(authUserProvider.future);
      if (user == null) {
        if (!mounted) return;
        context.go('/login');
        return;
      }

      final deviceId = await DeviceId.get();
      final repo = ref.read(licensingRepositoryProvider);

      final result = await repo.verifyLicense(
        keyString: _key.text.trim(),
        deviceId: deviceId,
      );

      if (!mounted) return;

      if (result.isPro) {
        ref.invalidate(isProProvider);
        ref.invalidate(licenseInfoProvider);
        ref.invalidate(profileStatusProvider);
        await OverlayMessage.success(context, 'License activated successfully');
        context.go('/dashboard');
      } else {
        const msg = 'License not active';
        setState(() => _error = msg);
        if (mounted) {
          await OverlayMessage.error(context, msg);
        }
      }
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

  Future<void> _signOut() async {
    if (mounted) context.go('/login');
    Future.microtask(() async {
      await ref.read(authRepositoryProvider).signOut();
    });
  }

  @override
  Widget build(BuildContext context) {
    final licenseAsync = ref.watch(licenseInfoProvider);
    final isProAsync = ref.watch(isProProvider);

    licenseAsync.whenData((lic) {
      if (lic == null) return;
      if (_key.text.trim().isNotEmpty) return;
      if (lic.keyString.trim().isEmpty) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_key.text.trim().isNotEmpty) return;
        _key.text = lic.keyString;
      });
    });

    return Scaffold(
     appBar: AppBar(
  leading: IconButton(
    icon: const Icon(Icons.arrow_back_rounded),
    tooltip: 'Back to dashboard',
    onPressed: _loading ? null : () => context.go('/dashboard'),
  ),
  title: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
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
        'Activate',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
      ),
    ],
  ),
  centerTitle: false,
  elevation: 0,
  actions: [
    IconButton(
      icon: const Icon(Icons.refresh_rounded),
      tooltip: 'Refresh',
      onPressed: _loading ? null : _refresh,
    ),
    IconButton(
      icon: const Icon(Icons.logout_rounded),
      tooltip: 'Sign out',
      onPressed: _loading ? null : _signOut,
    ),
  ],
),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                      Icon(
                        Icons.key,
                        size: 44,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Activate your license',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Enter your license key to unlock Pro features on this device.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Device ID: ${_deviceId ?? '...'}',
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 14),
                      licenseAsync.when(
                        data: (lic) {
                          if (lic == null) return const SizedBox.shrink();
                          final exp = lic.expiresAt?.toLocal().toString() ?? '-';
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Theme.of(context).dividerColor),
                              color: Theme.of(context).colorScheme.surface,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Current license',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: 6),
                                Text('Status: ${lic.status}'),
                                Text('Expires: $exp'),
                                const SizedBox(height: 6),
                                Text(
                                  'Key: ${lic.keyString}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          );
                        },
                        error: (_, __) => const SizedBox.shrink(),
                        loading: () => const SizedBox.shrink(),
                      ),
                      const SizedBox(height: 14),
                      AppTextField(controller: _key, label: 'License key'),
                      const SizedBox(height: 10),
                      licenseAsync.when(
                        data: (lic) {
                          if (lic == null || lic.keyString.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          return Text(
                            'Assigned key found for your account.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                          );
                        },
                        error: (_, __) => const SizedBox.shrink(),
                        loading: () => const SizedBox.shrink(),
                      ),
                      const SizedBox(height: 14),
                      isProAsync.when(
                        data: (isPro) {
                          return PrimaryButton(
                            label: isPro ? 'Verify / Re-activate' : 'Verify & Activate',
                            onPressed: _activate,
                            loading: _loading,
                          );
                        },
                        error: (_, __) => PrimaryButton(
                          label: 'Verify & Activate',
                          onPressed: _activate,
                          loading: _loading,
                        ),
                        loading: () => PrimaryButton(
                          label: 'Verify & Activate',
                          onPressed: _activate,
                          loading: _loading,
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton(
                        onPressed: _loading
                            ? null
                            : () async {
                                ref.invalidate(licenseInfoProvider);
                                ref.invalidate(isProProvider);
                                ref.invalidate(profileStatusProvider);
                                if (!mounted) return;
                                await OverlayMessage.info(context, 'License status refreshed.');
                              },
                        child: const Text('Refresh status'),
                      ),
                    ],
                  ),
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
