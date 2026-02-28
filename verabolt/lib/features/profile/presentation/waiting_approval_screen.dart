import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:verabolt/core/widgets/primary_button.dart';
import 'package:verabolt/features/auth/application/auth_providers.dart';
import 'package:verabolt/features/profile/application/profile_providers.dart';

class WaitingApprovalScreen extends ConsumerWidget {
  const WaitingApprovalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(profileStatusProvider);

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
      // Small logo — consistent branding across screens
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
        'Waiting for Approval',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
      ),
    ],
  ),
  centerTitle: false,  // left-aligned — looks balanced with back icon + logo
  elevation: 0,        // flat & clean (add 1 or 2 if you want subtle shadow)
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
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: status.when(
                data: (s) {
                  if (s == 'authorized') {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (context.mounted) context.go('/activate');
                    });
                  }

                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Icon(
                            Icons.schedule,
                            size: 44,
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Waiting for Admin Approval',
                            style: Theme.of(context).textTheme.titleLarge,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Your request has been submitted. An admin will assign a license key to your account soon.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 16),
                          PrimaryButton(
                            label: 'Refresh status',
                            onPressed: () => ref.invalidate(profileStatusProvider),
                          ),
                        ],
                      ),
                    ),
                  );
                },
                error: (e, _) => Text(e.toString()),
                loading: () => const SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
