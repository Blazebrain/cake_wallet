part of 'bitcoin_cash.dart';

class CWBitcoinCash extends BitcoinCash {
  @override
  String getCashAddrFormat(String address) => AddressUtils.getCashAddrFormat(address);

  @override
  WalletService createBitcoinCashWalletService(
    Box<WalletInfo> walletInfoSource,
    Box<UnspentCoinsInfo> unspentCoinSource,
    bool isDirect,
    bool mempoolAPIEnabled,
  ) {
    return BitcoinCashWalletService(
      walletInfoSource,
      unspentCoinSource,
      isDirect,
      mempoolAPIEnabled,
    );
  }

  @override
  WalletCredentials createBitcoinCashNewWalletCredentials({
    required String name,
    WalletInfo? walletInfo,
    String? password,
    String? passphrase,
    String? mnemonic,
    String? parentAddress,
  }) =>
      BitcoinCashNewWalletCredentials(
        name: name,
        walletInfo: walletInfo,
        password: password,
        passphrase: passphrase,
        parentAddress: parentAddress,
        mnemonic: mnemonic,
      );

  @override
  WalletCredentials createBitcoinCashRestoreWalletFromSeedCredentials(
          {required String name,
          required String mnemonic,
          required String password,
          String? passphrase}) =>
      BitcoinCashRestoreWalletFromSeedCredentials(
          name: name, mnemonic: mnemonic, password: password, passphrase: passphrase);

  @override
  TransactionPriority deserializeBitcoinCashTransactionPriority(int raw) =>
      ElectrumTransactionPriority.deserialize(raw: raw);

  @override
  TransactionPriority getDefaultTransactionPriority() => ElectrumTransactionPriority.medium;

  @override
  List<TransactionPriority> getTransactionPriorities() => ElectrumTransactionPriority.all;

  @override
  TransactionPriority getBitcoinCashTransactionPrioritySlow() => ElectrumTransactionPriority.slow;
}
