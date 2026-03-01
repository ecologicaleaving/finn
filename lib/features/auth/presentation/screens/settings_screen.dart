import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';

/// Settings screen that provides access to Profile and Group management.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Impostazioni'),
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('Profilo'),
            subtitle: const Text('Gestisci il tuo profilo personale'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.profile),
          ),
          ListTile(
            leading: const Icon(Icons.group),
            title: const Text('Gruppo'),
            subtitle: const Text('Gestisci il gruppo familiare'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.groupDetails),
          ),
          ListTile(
            leading: const Icon(Icons.category),
            title: const Text('Categorie'),
            subtitle: const Text('Gestisci categorie di spesa personalizzate'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.categoryManagement),
          ),
          ListTile(
            leading: const Icon(Icons.payment),
            title: const Text('Metodi di Pagamento'),
            subtitle: const Text('Gestisci i tuoi metodi di pagamento'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.paymentMethodManagement),
          ),
          ListTile(
            leading: const Icon(Icons.account_balance_wallet),
            title: const Text('Budget'),
            subtitle: const Text('Imposta e monitora i budget'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.budgetDashboard),
          ),
          // Feature 013-recurring-expenses T046-T047
          ListTile(
            leading: const Icon(Icons.loop),
            title: const Text('Spese ricorrenti'),
            subtitle: const Text('Gestisci spese ripetitive automatiche'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.recurringExpenses),
          ),
          // Feature 013-recurring-expenses T056-T057
          ListTile(
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: const Text('Rimborsi'),
            subtitle: const Text('Gestisci spese da rimborsare e rimborsate'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.reimbursements),
          ),
        ],
      ),
    );
  }
}
