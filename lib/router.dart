import 'package:cake_wallet/src/screens/dashboard/dashboard_page.dart';
import 'package:cake_wallet/src/screens/seed/wallet_seed_page.dart';
import 'package:cake_wallet/view_model/wallet_new_vm.dart';
import 'package:cake_wallet/view_model/wallet_restoration_from_seed_vm.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:hive/hive.dart';
import 'package:cake_wallet/routes.dart';
import 'package:cake_wallet/generated/i18n.dart';
import 'di.dart';
// MARK: Import domains

import 'package:cake_wallet/src/domain/common/contact.dart';
import 'package:cake_wallet/src/domain/services/user_service.dart';
import 'package:cake_wallet/src/domain/services/wallet_list_service.dart';
import 'package:cake_wallet/src/domain/services/wallet_service.dart';
import 'package:cake_wallet/src/domain/common/crypto_currency.dart';
import 'package:cake_wallet/src/domain/exchange/changenow/changenow_exchange_provider.dart';
import 'package:cake_wallet/src/domain/exchange/xmrto/xmrto_exchange_provider.dart';
import 'package:cake_wallet/src/domain/exchange/morphtoken/morphtoken_exchange_provider.dart';
import 'package:cake_wallet/src/domain/common/node.dart';
import 'package:cake_wallet/src/domain/monero/transaction_description.dart';
import 'package:cake_wallet/src/domain/exchange/trade.dart';
import 'package:cake_wallet/src/domain/monero/account.dart';
import 'package:cake_wallet/src/domain/common/mnemonic_item.dart';
import 'package:cake_wallet/src/domain/common/transaction_info.dart';
import 'package:cake_wallet/src/domain/monero/subaddress.dart';
import 'package:cake_wallet/src/domain/common/wallet_type.dart';

// MARK: Import stores

import 'package:cake_wallet/src/stores/authentication/authentication_store.dart';
import 'package:cake_wallet/src/stores/node_list/node_list_store.dart';
import 'package:cake_wallet/src/stores/auth/auth_store.dart';
import 'package:cake_wallet/src/stores/balance/balance_store.dart';
import 'package:cake_wallet/src/stores/send/send_store.dart';
import 'package:cake_wallet/src/stores/subaddress_creation/subaddress_creation_store.dart';
import 'package:cake_wallet/src/stores/subaddress_list/subaddress_list_store.dart';
import 'package:cake_wallet/src/stores/sync/sync_store.dart';
import 'package:cake_wallet/src/stores/user/user_store.dart';
import 'package:cake_wallet/src/stores/wallet/wallet_store.dart';
import 'package:cake_wallet/src/stores/wallet_creation/wallet_creation_store.dart';
import 'package:cake_wallet/src/stores/wallet_list/wallet_list_store.dart';
import 'package:cake_wallet/src/stores/wallet_restoration/wallet_restoration_store.dart';
import 'package:cake_wallet/src/stores/account_list/account_list_store.dart';
import 'package:cake_wallet/src/stores/address_book/address_book_store.dart';
import 'package:cake_wallet/src/stores/settings/settings_store.dart';
import 'package:cake_wallet/src/stores/wallet/wallet_keys_store.dart';
import 'package:cake_wallet/src/stores/exchange_trade/exchange_trade_store.dart';
import 'package:cake_wallet/src/stores/exchange/exchange_store.dart';
import 'package:cake_wallet/src/stores/rescan/rescan_wallet_store.dart';
import 'package:cake_wallet/src/stores/price/price_store.dart';

// MARK: Import screens

import 'package:cake_wallet/src/screens/auth/auth_page.dart';
import 'package:cake_wallet/src/screens/nodes/node_create_or_edit_page.dart';
import 'package:cake_wallet/src/screens/nodes/nodes_list_page.dart';
import 'package:cake_wallet/src/screens/receive/receive_page.dart';
import 'package:cake_wallet/src/screens/subaddress/address_edit_or_create_page.dart';
import 'package:cake_wallet/src/screens/wallet_list/wallet_list_page.dart';
import 'package:cake_wallet/src/screens/new_wallet/new_wallet_page.dart';
import 'package:cake_wallet/src/screens/setup_pin_code/setup_pin_code.dart';
import 'package:cake_wallet/src/screens/restore/restore_options_page.dart';
import 'package:cake_wallet/src/screens/restore/restore_wallet_options_page.dart';
import 'package:cake_wallet/src/screens/restore/restore_wallet_from_seed_page.dart';
import 'package:cake_wallet/src/screens/restore/restore_wallet_from_keys_page.dart';
import 'package:cake_wallet/src/screens/send/send_page.dart';
import 'package:cake_wallet/src/screens/disclaimer/disclaimer_page.dart';
import 'package:cake_wallet/src/screens/seed_language/seed_language_page.dart';
import 'package:cake_wallet/src/screens/transaction_details/transaction_details_page.dart';
import 'package:cake_wallet/src/screens/monero_accounts/monero_account_edit_or_create_page.dart';
import 'package:cake_wallet/src/screens/contact/contact_list_page.dart';
import 'package:cake_wallet/src/screens/contact/contact_page.dart';
import 'package:cake_wallet/src/screens/wallet_keys/wallet_keys_page.dart';
import 'package:cake_wallet/src/screens/exchange_trade/exchange_confirm_page.dart';
import 'package:cake_wallet/src/screens/exchange_trade/exchange_trade_page.dart';
import 'package:cake_wallet/src/screens/subaddress/subaddress_list_page.dart';
import 'package:cake_wallet/src/screens/settings/change_language.dart';
import 'package:cake_wallet/src/screens/restore/restore_wallet_from_seed_details.dart';
import 'package:cake_wallet/src/screens/exchange/exchange_page.dart';
import 'package:cake_wallet/src/screens/settings/settings.dart';
import 'package:cake_wallet/src/screens/rescan/rescan_page.dart';
import 'package:cake_wallet/src/screens/faq/faq_page.dart';
import 'package:cake_wallet/src/screens/trade_details/trade_details_page.dart';
import 'package:cake_wallet/src/screens/auth/create_unlock_page.dart';
import 'package:cake_wallet/src/screens/auth/create_login_page.dart';
import 'package:cake_wallet/src/screens/dashboard/create_dashboard_page.dart';
import 'package:cake_wallet/src/screens/welcome/create_welcome_page.dart';
import 'package:cake_wallet/src/screens/new_wallet/new_wallet_type_page.dart';
import 'package:cake_wallet/src/screens/send/send_template_page.dart';
import 'package:cake_wallet/src/screens/exchange/exchange_template_page.dart';

class Router {
  static Route<dynamic> generateRoute(
      {SharedPreferences sharedPreferences,
      WalletListService walletListService,
      WalletService walletService,
      UserService userService,
      RouteSettings settings,
      PriceStore priceStore,
      WalletStore walletStore,
      SyncStore syncStore,
      BalanceStore balanceStore,
      SettingsStore settingsStore,
      Box<Contact> contacts,
      Box<Node> nodes,
      Box<TransactionDescription> transactionDescriptions,
      Box<Trade> trades}) {
    switch (settings.name) {
      case Routes.welcome:
        return MaterialPageRoute<void>(builder: (_) => createWelcomePage());

      case Routes.newWalletFromWelcome:
        final type = settings.arguments as WalletType;
        walletListService.changeWalletManger(walletType: type);

        return CupertinoPageRoute<void>(
            builder: (_) => Provider(
                create: (_) => UserStore(
                    accountService: UserService(
                        secureStorage: FlutterSecureStorage(),
                        sharedPreferences: sharedPreferences)),
                child: SetupPinCodePage(
                    onPinCodeSetup: (context, _) =>
                        Navigator.pushNamed(context, Routes.newWalletType))));

      case Routes.newWalletType:
        return CupertinoPageRoute<void>(
            builder: (_) => NewWalletTypePage(
                  onTypeSelected: (context, type) => Navigator.of(context)
                      .pushNamed(Routes.newWallet, arguments: type),
                ));

      case Routes.newWallet:
        final type = settings.arguments as WalletType;
        final walletNewVM = getIt.get<WalletNewVM>(param1: type);

        return CupertinoPageRoute<void>(
            builder: (_) => NewWalletPage(walletNewVM));

      case Routes.setupPin:
        Function(BuildContext, String) callback;

        if (settings.arguments is Function(BuildContext, String)) {
          callback = settings.arguments as Function(BuildContext, String);
        }

        return CupertinoPageRoute<void>(
            builder: (_) => Provider(
                create: (_) => UserStore(
                    accountService: UserService(
                        secureStorage: FlutterSecureStorage(),
                        sharedPreferences: sharedPreferences)),
                child: SetupPinCodePage(
                    onPinCodeSetup: (context, pin) =>
                        callback == null ? null : callback(context, pin))),
            fullscreenDialog: true);

      case Routes.restoreWalletType:
        return CupertinoPageRoute<void>(
            builder: (_) => NewWalletTypePage(
                  onTypeSelected: (context, type) => Navigator.of(context)
                      .pushNamed(Routes.restoreWalletOptions, arguments: type),
                ));

      case Routes.restoreOptions:
        final type = settings.arguments as WalletType;
        walletListService.changeWalletManger(walletType: type);

        return CupertinoPageRoute<void>(
            builder: (_) => RestoreOptionsPage(type: type));

      case Routes.restoreWalletOptions:
        final type = settings.arguments as WalletType;
        walletListService.changeWalletManger(walletType: type);

        return CupertinoPageRoute<void>(
            builder: (_) => RestoreWalletOptionsPage(
                type: type,
                onRestoreFromSeed: (context) {
                  final route = type == WalletType.monero
                      ? Routes.seedLanguage
                      : Routes.restoreWalletFromSeed;
                  final args = type == WalletType.monero
                      ? [type, Routes.restoreWalletFromSeed]
                      : [type];

                  Navigator.of(context).pushNamed(route, arguments: args);
                },
                onRestoreFromKeys: (context) {
                  final route = type == WalletType.monero
                      ? Routes.seedLanguage
                      : Routes.restoreWalletFromKeys;
                  final args = type == WalletType.monero
                      ? [type, Routes.restoreWalletFromSeed]
                      : [type];

                  Navigator.of(context).pushNamed(route, arguments: args);
                }));

      case Routes.restoreWalletOptionsFromWelcome:
        return CupertinoPageRoute<void>(
            builder: (_) => Provider(
                create: (_) => UserStore(
                    accountService: UserService(
                        secureStorage: FlutterSecureStorage(),
                        sharedPreferences: sharedPreferences)),
                child: SetupPinCodePage(
                    onPinCodeSetup: (context, _) => Navigator.pushNamed(
                        context, Routes.restoreWalletType))));

      case Routes.seed:
        return MaterialPageRoute<void>(
            builder: (_) => getIt.get<WalletSeedPage>(
                param1: settings.arguments as VoidCallback));

      case Routes.restoreWalletFromSeed:
        final args = settings.arguments as List<dynamic>;
        final type = args.first as WalletType;
        final language = type == WalletType.monero
            ? args[1] as String
            : 'English'; // FIXME: Unnamed constant; English default and only one language for bitcoin.

        return CupertinoPageRoute<void>(
            builder: (_) =>
                RestoreWalletFromSeedPage(type: type, language: language));

      case Routes.restoreWalletFromKeys:
        final args = settings.arguments as List<dynamic>;
        final type = args.first as WalletType;
        final language = type == WalletType.monero
            ? args[1] as String
            : 'English'; // FIXME: Unnamed constant; English default and only one language for bitcoin.

        return CupertinoPageRoute<void>(
            builder: (_) =>
                ProxyProvider<AuthenticationStore, WalletRestorationStore>(
                    update: (_, authStore, __) => WalletRestorationStore(
                        authStore: authStore,
                        sharedPreferences: sharedPreferences,
                        walletListService: walletListService),
                    child: RestoreWalletFromKeysPage(
                        walletsService: walletListService,
                        walletService: walletService,
                        sharedPreferences: sharedPreferences)));

      case Routes.dashboard:
        return CupertinoPageRoute<void>(
            builder: (_) => getIt.get<DashboardPage>());

      case Routes.send:
        return CupertinoPageRoute<void>(
            fullscreenDialog: true, builder: (_) => getIt.get<SendPage>());

      case Routes.sendTemplate:
        return CupertinoPageRoute<void>(
            fullscreenDialog: true, builder: (_) => getIt.get<SendTemplatePage>());

      case Routes.receive:
        return CupertinoPageRoute<void>(
            fullscreenDialog: true, builder: (_) => getIt.get<ReceivePage>());

      case Routes.transactionDetails:
        return CupertinoPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => TransactionDetailsPage(
                transactionInfo: settings.arguments as TransactionInfo));

      case Routes.newSubaddress:
        return CupertinoPageRoute<void>(
            builder: (_) =>
                getIt.get<AddressEditOrCreatePage>(param1: settings.arguments));

      case Routes.disclaimer:
        return CupertinoPageRoute<void>(builder: (_) => DisclaimerPage());

      case Routes.readDisclaimer:
        return CupertinoPageRoute<void>(
            builder: (_) => DisclaimerPage(isReadOnly: true));

      case Routes.seedLanguage:
        final args = settings.arguments as List<dynamic>;
        final type = args.first as WalletType;
        final redirectRoute = args[1] as String;

        return CupertinoPageRoute<void>(builder: (_) {
          return SeedLanguage(
              onConfirm: (context, lang) => Navigator.of(context)
                  .popAndPushNamed(redirectRoute, arguments: [type, lang]));
        });

      case Routes.walletList:
        return MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => getIt.get<WalletListPage>());

      case Routes.auth:
        return MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => getIt.get<AuthPage>(
                param1: settings.arguments as OnAuthenticationFinished));

      case Routes.unlock:
        return MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => createUnlockPage(
                sharedPreferences: sharedPreferences,
                userService: userService,
                walletService: walletService,
                onAuthenticationFinished:
                    settings.arguments as OnAuthenticationFinished));

      case Routes.nodeList:
        return CupertinoPageRoute<void>(
            builder: (_) => getIt.get<NodeListPage>());

      case Routes.newNode:
        return CupertinoPageRoute<void>(
            builder: (_) => getIt.get<NodeCreateOrEditPage>());

      case Routes.login:
        return CupertinoPageRoute<void>(builder: (context) {
          final authenticationStore = Provider.of<AuthenticationStore>(context);

          return createLoginPage(
              sharedPreferences: sharedPreferences,
              userService: userService,
              walletService: walletService,
              walletListService: walletListService,
              authenticationStore: authenticationStore);
        });

      case Routes.accountCreation:
        return CupertinoPageRoute<String>(
            builder: (_) => getIt.get<MoneroAccountEditOrCreatePage>());

      case Routes.addressBook:
        return MaterialPageRoute<void>(
            builder: (_) => getIt.get<ContactListPage>());

      case Routes.pickerAddressBook:
        return MaterialPageRoute<void>(
            builder: (_) => getIt.get<ContactListPage>());

      case Routes.addressBookAddContact:
        return CupertinoPageRoute<void>(
            builder: (_) =>
                getIt.get<ContactPage>(param1: settings.arguments as Contact));

      case Routes.showKeys:
        return MaterialPageRoute<void>(
            builder: (_) => getIt.get<WalletKeysPage>(),
            fullscreenDialog: true);

      case Routes.exchangeTrade:
        return CupertinoPageRoute<void>(
            builder: (_) => getIt.get<ExchangeTradePage>());

                /*MultiProvider(
                  providers: [
                    ProxyProvider<SettingsStore, ExchangeTradeStore>(
                      update: (_, settingsStore, __) => ExchangeTradeStore(
                          trade: settings.arguments as Trade,
                          walletStore: walletStore,
                          trades: trades),
                    ),
                    ProxyProvider<SettingsStore, SendStore>(
                        update: (_, settingsStore, __) => SendStore(
                            transactionDescriptions: transactionDescriptions,
                            walletService: walletService,
                            settingsStore: settingsStore,
                            priceStore: priceStore)),
                  ],
                  child: ExchangeTradePage(),
                ));*/

      case Routes.exchangeConfirm:
        return MaterialPageRoute<void>(
            builder: (_) => getIt.get<ExchangeConfirmPage>());

                //ExchangeConfirmPage(trade: settings.arguments as Trade));

      case Routes.tradeDetails:
        return MaterialPageRoute<void>(builder: (context) {
          return MultiProvider(providers: [
            ProxyProvider<SettingsStore, ExchangeTradeStore>(
              update: (_, settingsStore, __) => ExchangeTradeStore(
                  trade: settings.arguments as Trade,
                  walletStore: walletStore,
                  trades: trades),
            )
          ], child: TradeDetailsPage());
        });

      case Routes.subaddressList:
        return MaterialPageRoute<Subaddress>(
            builder: (_) => MultiProvider(providers: [
                  Provider(
                      create: (_) =>
                          SubaddressListStore(walletService: walletService))
                ], child: SubaddressListPage()));

      case Routes.restoreWalletFromSeedDetails:
        final args = settings.arguments as List;
        final walletRestorationFromSeedVM =
            getIt.get<WalletRestorationFromSeedVM>(param1: args);

        return CupertinoPageRoute<void>(
            builder: (_) => RestoreWalletFromSeedDetailsPage(
                walletRestorationFromSeedVM: walletRestorationFromSeedVM));

      case Routes.exchange:
        return CupertinoPageRoute<void>(
            builder: (_) => getIt.get<ExchangePage>());

      case Routes.exchangeTemplate:
        return CupertinoPageRoute<void>(
            builder: (_) => getIt.get<ExchangeTemplatePage>());

      case Routes.settings:
        return MaterialPageRoute<void>(
            builder: (_) => getIt.get<SettingsPage>());

      case Routes.rescan:
        return MaterialPageRoute<void>(
            builder: (_) => Provider(
                create: (_) => RescanWalletStore(walletService: walletService),
                child: RescanPage()));

      case Routes.faq:
        return MaterialPageRoute<void>(builder: (_) => FaqPage());

      case Routes.changeLanguage:
        return MaterialPageRoute<void>(builder: (_) => ChangeLanguage());

      default:
        return MaterialPageRoute<void>(
            builder: (_) => Scaffold(
                  body: Center(
                      child: Text(S.current.router_no_route(settings.name))),
                ));
    }
  }
}
