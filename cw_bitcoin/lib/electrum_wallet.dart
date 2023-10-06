import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:cw_bitcoin/encryption_file_utils.dart';
import 'package:cw_core/unspent_coins_info.dart';
import 'package:hive/hive.dart';
import 'package:cw_bitcoin/electrum_wallet_addresses.dart';
import 'package:mobx/mobx.dart';
import 'package:rxdart/subjects.dart';
import 'package:flutter/foundation.dart';
import 'package:bitcoin_flutter/bitcoin_flutter.dart' as bitcoin;
import 'package:cw_bitcoin/electrum_transaction_info.dart';
import 'package:cw_core/pathForWallet.dart';
import 'package:cw_bitcoin/address_to_output_script.dart';
import 'package:cw_bitcoin/bitcoin_address_record.dart';
import 'package:cw_bitcoin/electrum_balance.dart';
import 'package:cw_bitcoin/bitcoin_transaction_credentials.dart';
import 'package:cw_bitcoin/electrum_transaction_history.dart';
import 'package:cw_bitcoin/bitcoin_transaction_no_inputs_exception.dart';
import 'package:cw_bitcoin/bitcoin_transaction_priority.dart';
import 'package:cw_bitcoin/bitcoin_transaction_wrong_balance_exception.dart';
import 'package:cw_bitcoin/bitcoin_unspent.dart';
import 'package:cw_bitcoin/bitcoin_wallet_keys.dart';
import 'package:cw_bitcoin/pending_bitcoin_transaction.dart';
import 'package:cw_bitcoin/script_hash.dart';
import 'package:cw_bitcoin/utils.dart';
import 'package:cw_core/wallet_base.dart';
import 'package:cw_core/node.dart';
import 'package:cw_core/sync_status.dart';
import 'package:cw_core/transaction_priority.dart';
import 'package:cw_core/wallet_info.dart';
import 'package:cw_bitcoin/electrum.dart';
import 'package:hex/hex.dart';
import 'package:cw_core/crypto_currency.dart';
import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;

part 'electrum_wallet.g.dart';

class ElectrumWallet = ElectrumWalletBase with _$ElectrumWallet;

abstract class ElectrumWalletBase
    extends WalletBase<ElectrumBalance, ElectrumTransactionHistory, ElectrumTransactionInfo>
    with Store {
  ElectrumWalletBase(
      {required String password,
      required WalletInfo walletInfo,
      required Box<UnspentCoinsInfo> unspentCoinsInfo,
      required this.networkType,
      required this.mnemonic,
      required Uint8List seedBytes,
      required this.encryptionFileUtils,
      List<BitcoinAddressRecord>? initialAddresses,
      ElectrumClient? electrumClient,
      ElectrumBalance? initialBalance,
      CryptoCurrency? currency})
      : hd = bitcoin.HDWallet.fromSeed(seedBytes, network: networkType).derivePath("m/0'/0"),
        syncStatus = NotConnectedSyncStatus(),
        _password = password,
        _feeRates = <int>[],
        _isTransactionUpdating = false,
        unspentCoins = [],
        _scripthashesUpdateSubject = {},
        balance = ObservableMap<CryptoCurrency, ElectrumBalance>.of(currency != null
            ? {
                currency:
                    initialBalance ?? const ElectrumBalance(confirmed: 0, unconfirmed: 0, frozen: 0)
              }
            : {}),
        this.unspentCoinsInfo = unspentCoinsInfo,
        super(walletInfo) {
    this.electrumClient = electrumClient ?? ElectrumClient();
    this.walletInfo = walletInfo;
    transactionHistory = ElectrumTransactionHistory(
        walletInfo: walletInfo, password: password, encryptionFileUtils: encryptionFileUtils);
  }

  static int estimatedTransactionSize(int inputsCount, int outputsCounts) =>
      inputsCount * 146 + outputsCounts * 33 + 8;

  final bitcoin.HDWallet hd;
  final String mnemonic;
  final EncryptionFileUtils encryptionFileUtils;

  late ElectrumClient electrumClient;
  Box<UnspentCoinsInfo> unspentCoinsInfo;

  @override
  late ElectrumWalletAddresses walletAddresses;

  @override
  @observable
  late ObservableMap<CryptoCurrency, ElectrumBalance> balance;

  @override
  @observable
  SyncStatus syncStatus;

  List<String> get scriptHashes => walletAddresses.addresses
      .map((addr) => scriptHash(addr.address, networkType: networkType))
      .toList();

  List<String> get publicScriptHashes => walletAddresses.addresses
      .where((addr) => !addr.isHidden)
      .map((addr) => scriptHash(addr.address, networkType: networkType))
      .toList();

  String get xpub => hd.base58!;

  @override
  String get seed => mnemonic;

  @override
  String get password => _password;

  bitcoin.NetworkType networkType;

  @override
  BitcoinWalletKeys get keys =>
      BitcoinWalletKeys(wif: hd.wif!, privateKey: hd.privKey!, publicKey: hd.pubKey!);

  String _password;
  List<BitcoinUnspent> unspentCoins;
  List<int> _feeRates;
  Map<String, BehaviorSubject<Object>?> _scripthashesUpdateSubject;
  bool _isTransactionUpdating;

  void Function(FlutterErrorDetails)? _onError;

  Future<void> init() async {
    await walletAddresses.init();
    await transactionHistory.init();
    await save();
  }

  @action
  @override
  Future<void> startSync() async {
    try {
      syncStatus = AttemptingSyncStatus();
      await walletAddresses.discoverAddresses();
      await updateTransactions();
      _subscribeForUpdates();
      await updateUnspent();
      await updateBalance();
      _feeRates = await electrumClient.feeRates();

      Timer.periodic(
          const Duration(minutes: 1), (timer) async => _feeRates = await electrumClient.feeRates());

      syncStatus = SyncedSyncStatus();
    } catch (e, stacktrace) {
      print(stacktrace);
      print(e.toString());
      syncStatus = FailedSyncStatus();
    }
  }

  @action
  @override
  Future<void> connectToNode({required Node node}) async {
    try {
      syncStatus = ConnectingSyncStatus();
      await electrumClient.connectToUri(node.uri);
      electrumClient.onConnectionStatusChange = (bool isConnected) {
        if (!isConnected) {
          syncStatus = LostConnectionSyncStatus();
        }
      };
      syncStatus = ConnectedSyncStatus();
    } catch (e) {
      print(e.toString());
      syncStatus = FailedSyncStatus();
    }
  }

  @override
  Future<PendingBitcoinTransaction> createTransaction(Object credentials) async {
    const minAmount = 546;
    final transactionCredentials = credentials as BitcoinTransactionCredentials;
    final inputs = <BitcoinUnspent>[];
    final outputs = transactionCredentials.outputs;
    final hasMultiDestination = outputs.length > 1;
    var allInputsAmount = 0;

    if (unspentCoins.isEmpty) {
      await updateUnspent();
    }

    for (final utx in unspentCoins) {
      if (utx.isSending) {
        allInputsAmount += utx.value;
        inputs.add(utx);
      }
    }

    if (inputs.isEmpty) {
      throw BitcoinTransactionNoInputsException();
    }

    final allAmountFee = 188;

    final allAmount = allInputsAmount - allAmountFee;

    var credentialsAmount = 0;
    var amount = 0;
    var fee = 0;

    if (hasMultiDestination) {
      if (outputs.any((item) => item.sendAll || item.formattedCryptoAmount! <= 0)) {
        throw BitcoinTransactionWrongBalanceException(currency);
      }

      credentialsAmount = outputs.fold(0, (acc, value) => acc + value.formattedCryptoAmount!);

      if (allAmount - credentialsAmount < minAmount) {
        throw BitcoinTransactionWrongBalanceException(currency);
      }

      amount = credentialsAmount;

      if (transactionCredentials.feeRate != null) {
        fee = calculateEstimatedFeeWithFeeRate(transactionCredentials.feeRate!, amount,
            outputsCount: outputs.length + 1);
      } else {
        fee = calculateEstimatedFee(transactionCredentials.priority, amount,
            outputsCount: outputs.length + 1);
      }
    } else {
      final output = outputs.first;
      credentialsAmount = !output.sendAll ? output.formattedCryptoAmount! : 0;

      if (credentialsAmount > allAmount) {
        throw BitcoinTransactionWrongBalanceException(currency);
      }

      amount = output.sendAll || allAmount - credentialsAmount < minAmount
          ? allAmount
          : credentialsAmount;

      if (output.sendAll || amount == allAmount) {
        fee = allAmountFee;
      } else if (transactionCredentials.feeRate != null) {
        fee = calculateEstimatedFeeWithFeeRate(transactionCredentials.feeRate!, amount);
      } else {
        fee = calculateEstimatedFee(transactionCredentials.priority, amount);
      }
    }

    if (fee == 0 && networkType == bitcoin.bitcoin) {
      // throw BitcoinTransactionWrongBalanceException(currency);
    }

    final totalAmount = amount + fee;

    if (totalAmount > balance[currency]!.confirmed || totalAmount > allInputsAmount) {
      // throw BitcoinTransactionWrongBalanceException(currency);
    }

    final txb = bitcoin.TransactionBuilder(network: networkType);
    final changeAddress = await walletAddresses.getChangeAddress();
    var leftAmount = totalAmount;
    var totalInputAmount = 0;

    inputs.clear();

    for (final utx in unspentCoins) {
      if (utx.isSending) {
        leftAmount = leftAmount - utx.value;
        totalInputAmount += utx.value;
        inputs.add(utx);

        if (leftAmount <= 0) {
          break;
        }
      }
    }

    if (inputs.isEmpty) {
      throw BitcoinTransactionNoInputsException();
    }

    if (amount <= 0 || totalInputAmount < totalAmount) {
      // throw BitcoinTransactionWrongBalanceException(currency);
    }

    txb.setVersion(1);
    List<bitcoin.PrivateKeyInfo> privateKeys = [];
    List<bitcoin.Outpoint> outpoints = [];
    inputs.forEach((input) {
      privateKeys.add(bitcoin.PrivateKeyInfo(
          bitcoin.ECPrivateKey(Uint8List.fromList(
              HEX.decode(walletAddresses.sideHd.derive(input.address.index).privKey!))),
          false));
      outpoints.add(bitcoin.Outpoint(Uint8List.fromList(HEX.decode(input.hash)), input.vout));

      if (input.isP2wpkh) {
        final p2wpkh = bitcoin
            .P2WPKH(
                data: generatePaymentData(
                    hd: input.address.isHidden ? walletAddresses.sideHd : walletAddresses.mainHd,
                    index: input.address.index),
                network: networkType)
            .data;

        txb.addInput(input.hash, input.vout, null, p2wpkh.output);
      } else {
        txb.addInput(input.hash, input.vout);
      }
    });

    List<bitcoin.SilentPaymentDestination> silentDestinations = [];
    outputs.forEach((item) {
      final outputAmount = hasMultiDestination ? item.formattedCryptoAmount : amount;
      final outputAddress = item.isParsedAddress ? item.extractedAddress! : item.address;
      if (outputAddress.startsWith('tsp1')) {
        silentDestinations
            .add(bitcoin.SilentPaymentDestination.fromAddress(outputAddress, outputAmount!));
      } else {
        txb.addOutput(addressToOutputScript(outputAddress, networkType), outputAmount!);
      }
    });

    if (silentDestinations.isNotEmpty) {
      final outpointsHash = bitcoin.SilentPayment.hashOutpoints(outpoints);

      final sumOfInputPrivKeys = bitcoin.getSumInputPrivKeys(privateKeys);

      final generatedPubkeys = bitcoin.SilentPayment.generateMultipleRecipientPubkeys(
          sumOfInputPrivKeys, outpointsHash, silentDestinations);

      generatedPubkeys.forEach((recipientSilentAddress, generatedOutputs) {
        generatedOutputs.forEach((output) {
          final generatedPubkey = HEX.encode(output.$1.data);
          txb.addOutput(bitcoin.getTaproot(generatedPubkey).toScriptPubKey().toBytes(), output.$2);
        });
      });
    }

    final estimatedSize = estimatedTransactionSize(inputs.length, outputs.length + 1);
    var feeAmount = 188;

    // if (transactionCredentials.feeRate != null) {
    //   feeAmount = transactionCredentials.feeRate! * estimatedSize;
    // } else {
    //   feeAmount = feeRate(transactionCredentials.priority!) * estimatedSize;
    // }

    final changeValue = totalInputAmount - amount - feeAmount;

    if (changeValue > minAmount) {
      txb.addOutput(changeAddress, changeValue);
    }

    for (var i = 0; i < inputs.length; i++) {
      final input = inputs[i];
      final keyPair = generateKeyPair(
          hd: input.address.isHidden ? walletAddresses.sideHd : walletAddresses.mainHd,
          index: input.address.index,
          network: networkType);
      final witnessValue = input.isP2wpkh ? input.value : null;

      txb.sign(vin: i, keyPair: keyPair, witnessValue: witnessValue);
    }

    return PendingBitcoinTransaction(txb.build(), type,
        electrumClient: electrumClient, amount: amount, fee: fee)
      ..addListener((transaction) async {
        transactionHistory.addOne(transaction);
        await updateBalance();
      });
  }

  String toJSON() => json.encode({
        'mnemonic': mnemonic,
        'account_index': walletAddresses.currentReceiveAddressIndex.toString(),
        'change_address_index': walletAddresses.currentChangeAddressIndex.toString(),
        'addresses': walletAddresses.addresses.map((addr) => addr.toJSON()).toList(),
        'balance': balance[currency]?.toJSON(),
        'network_type': networkType.toString()
      });

  int feeRate(TransactionPriority priority) {
    try {
      if (priority is BitcoinTransactionPriority) {
        return _feeRates[priority.raw];
      }

      return 0;
    } catch (_) {
      return 0;
    }
  }

  int feeAmountForPriority(
          BitcoinTransactionPriority priority, int inputsCount, int outputsCount) =>
      feeRate(priority) * estimatedTransactionSize(inputsCount, outputsCount);

  int feeAmountWithFeeRate(int feeRate, int inputsCount, int outputsCount) =>
      feeRate * estimatedTransactionSize(inputsCount, outputsCount);

  @override
  int calculateEstimatedFee(TransactionPriority? priority, int? amount, {int? outputsCount}) {
    if (priority is BitcoinTransactionPriority) {
      return calculateEstimatedFeeWithFeeRate(feeRate(priority), amount,
          outputsCount: outputsCount);
    }

    return 0;
  }

  int calculateEstimatedFeeWithFeeRate(int feeRate, int? amount, {int? outputsCount}) {
    int inputsCount = 0;

    if (amount != null) {
      int totalValue = 0;

      for (final input in unspentCoins) {
        if (totalValue >= amount) {
          break;
        }

        if (input.isSending) {
          totalValue += input.value;
          inputsCount += 1;
        }
      }

      if (totalValue < amount) return 0;
    } else {
      for (final input in unspentCoins) {
        if (input.isSending) {
          inputsCount += 1;
        }
      }
    }

    // If send all, then we have no change value
    final _outputsCount = outputsCount ?? (amount != null ? 2 : 1);

    return feeAmountWithFeeRate(feeRate, inputsCount, _outputsCount);
  }

  @override
  Future<void> save() async {
    final path = await makePath();
    await encryptionFileUtils.write(path: path, password: _password, data: toJSON());
    await transactionHistory.save();
  }

  @override
  Future<void> renameWalletFiles(String newWalletName) async {
    final currentWalletPath = await pathForWallet(name: walletInfo.name, type: type);
    final currentWalletFile = File(currentWalletPath);

    final currentDirPath = await pathForWalletDir(name: walletInfo.name, type: type);
    final currentTransactionsFile = File('$currentDirPath/$transactionsHistoryFileName');

    // Copies current wallet files into new wallet name's dir and files
    if (currentWalletFile.existsSync()) {
      final newWalletPath = await pathForWallet(name: newWalletName, type: type);
      await currentWalletFile.copy(newWalletPath);
    }
    if (currentTransactionsFile.existsSync()) {
      final newDirPath = await pathForWalletDir(name: newWalletName, type: type);
      await currentTransactionsFile.copy('$newDirPath/$transactionsHistoryFileName');
    }

    // Delete old name's dir and files
    await Directory(currentDirPath).delete(recursive: true);
  }

  @override
  Future<void> changePassword(String password) async {
    _password = password;
    await save();
    await transactionHistory.changePassword(password);
  }

  bitcoin.ECPair keyPairFor({required int index}) =>
      generateKeyPair(hd: hd, index: index, network: networkType);

  @override
  Future<void> rescan({required int height}) async => throw UnimplementedError();

  @override
  Future<void> close() async {
    try {
      await electrumClient.close();
    } catch (_) {}
  }

  Future<String> makePath() async => pathForWallet(name: walletInfo.name, type: walletInfo.type);

  Future<void> updateUnspent() async {
    final unspent = await Future.wait(walletAddresses.addresses.map((address) => electrumClient
        .getListUnspentWithAddress(address.address, networkType)
        .then((unspent) => unspent.map((unspent) {
              try {
                return BitcoinUnspent.fromJSON(address, unspent);
              } catch (_) {
                return null;
              }
            }).whereNotNull())));
    final uri = Uri(
        scheme: 'https',
        host: 'blockstream.info',
        path: '/testnet/api/tx/986547a4daec37b21d2252e39c740d77ff92d927343b0b6e017d45e857955efa');

    await http.get(uri).then((response) {
      final obj = json.decode(response.body);
      final scanPrivateKey = walletAddresses.silentAddress!.scanPrivkey;
      final spendPublicKey = walletAddresses.silentAddress!.spendPubkey;
      Uint8List? sumOfInputPublicKeys;
      List<bitcoin.Outpoint> outpoints = [];
      obj["vin"].forEach((input) {
        sumOfInputPublicKeys = Uint8List.fromList(HEX.decode(input["witness"][1] as String));
        outpoints.add(bitcoin.Outpoint(
            Uint8List.fromList(HEX.decode(input['txid'] as String)), input['vout'] as int));
      });
      final outpointHash = bitcoin.SilentPayment.hashOutpoints(outpoints);
      List<Uint8List> outputs = [];
      obj['vout'].forEach((out) {
        outputs.add(Uint8List.fromList(
            HEX.decode(bitcoin.getScript(out["scriptpubkey"] as String)[1] as String)));
      });
      final result = bitcoin.scanOutputs(
          scanPrivateKey.data, spendPublicKey.data, sumOfInputPublicKeys!, outpointHash, outputs);
      result.forEach((key, value) {
        final tweak = value;
        // TODO: store tweak for BitcoinUnspent
        final spendPrivateKey = walletAddresses.silentAddress!.spendPrivkey;
        final privKey = spendPrivateKey.tweak(tweak);
        final pubKey = bitcoin.ECPrivateKey(privKey!.data).pubkey;
        int i = 0;
        final vout = obj['vout'].firstWhere((out) {
          final script = bitcoin.getScript(out["scriptpubkey"] as String);
          final scriptHash = script[1] as String;
          i++;
          return scriptHash == key;
        });
        unspent.add([
          BitcoinUnspent.fromJSON(
              BitcoinAddressRecord(vout["scriptpubkey_address"] as String, index: 0, isUsed: true),
              {"tx_hash": obj["txid"], "value": vout["value"], "tx_pos": i},
              isSilent: true)
        ]);
      });
    });
    unspentCoins = unspent.expand((e) => e).toList();

    if (unspentCoinsInfo.isEmpty) {
      unspentCoins.forEach((coin) => _addCoinInfo(coin));
      return;
    }

    if (unspentCoins.isNotEmpty) {
      unspentCoins.forEach((coin) {
        final coinInfoList = unspentCoinsInfo.values.where((element) =>
            element.walletId.contains(id) &&
            element.hash.contains(coin.hash) &&
            element.address.contains(coin.address.address));

        if (coinInfoList.isNotEmpty) {
          final coinInfo = coinInfoList.first;

          coin.isFrozen = coinInfo.isFrozen;
          coin.isSending = coinInfo.isSending;
          coin.note = coinInfo.note;
        } else {
          _addCoinInfo(coin);
        }
      });
    }

    await _refreshUnspentCoinsInfo();
  }

  Future<void> _addCoinInfo(BitcoinUnspent coin) async {
    final newInfo = UnspentCoinsInfo(
      walletId: id,
      hash: coin.hash,
      isFrozen: coin.isFrozen,
      isSending: coin.isSending,
      noteRaw: coin.note,
      address: coin.address.address,
      value: coin.value,
      vout: coin.vout,
    );

    await unspentCoinsInfo.add(newInfo);
  }

  Future<void> _refreshUnspentCoinsInfo() async {
    try {
      final List<dynamic> keys = <dynamic>[];
      final currentWalletUnspentCoins =
          unspentCoinsInfo.values.where((element) => element.walletId.contains(id));

      if (currentWalletUnspentCoins.isNotEmpty) {
        currentWalletUnspentCoins.forEach((element) {
          final existUnspentCoins = unspentCoins.where((coin) => element.hash.contains(coin.hash));

          if (existUnspentCoins.isEmpty) {
            keys.add(element.key);
          }
        });
      }

      if (keys.isNotEmpty) {
        await unspentCoinsInfo.deleteAll(keys);
      }
    } catch (e) {
      print(e.toString());
    }
  }

  Future<ElectrumTransactionBundle> getTransactionExpanded(
      {required String hash, required int height}) async {
    final verboseTransaction =
        await electrumClient.getTransactionRaw(hash: hash, networkType: networkType);

    String transactionHex;
    int? time;
    int confirmations = 0;
    if (networkType == bitcoin.testnet) {
      transactionHex = verboseTransaction as String;
      confirmations = 1;
    } else {
      transactionHex = verboseTransaction['hex'] as String;
      time = verboseTransaction['time'] as int?;
      confirmations = verboseTransaction['confirmations'] as int? ?? 0;
    }

    final original = bitcoin.Transaction.fromHex(transactionHex);
    final ins = <bitcoin.Transaction>[];

    for (final vin in original.ins) {
      final id = HEX.encode(vin.hash!.reversed.toList());
      final txHex = await electrumClient.getTransactionHex(hash: id);
      final tx = bitcoin.Transaction.fromHex(txHex);
      ins.add(tx);
    }

    return ElectrumTransactionBundle(original, ins: ins, time: time, confirmations: confirmations);
  }

  Future<ElectrumTransactionInfo?> fetchTransactionInfo(
      {required String hash, required int height}) async {
    try {
      final tx = await getTransactionExpanded(hash: hash, height: height);
      final addresses = walletAddresses.addresses.map((addr) => addr.address).toSet();
      return ElectrumTransactionInfo.fromElectrumBundle(tx, walletInfo.type, networkType,
          addresses: addresses, height: height);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Map<String, ElectrumTransactionInfo>> fetchTransactions() async {
    final addressHashes = <String, BitcoinAddressRecord>{};
    final normalizedHistories = <Map<String, dynamic>>[];
    walletAddresses.addresses.forEach((addressRecord) {
      final sh = scriptHash(addressRecord.address, networkType: networkType);
      addressHashes[sh] = addressRecord;
    });
    final histories = addressHashes.keys.map((scriptHash) =>
        electrumClient.getHistory(scriptHash).then((history) => {scriptHash: history}));
    final historyResults = await Future.wait(histories);
    historyResults.forEach((history) {
      history.entries.forEach((historyItem) {
        if (historyItem.value.isNotEmpty) {
          final address = addressHashes[historyItem.key];
          address?.setAsUsed();
          normalizedHistories.addAll(historyItem.value);
        }
      });
    });
    final historiesWithDetails = await Future.wait(normalizedHistories.map((transaction) {
      try {
        return fetchTransactionInfo(
            hash: transaction['tx_hash'] as String, height: transaction['height'] as int);
      } catch (_) {
        return Future.value(null);
      }
    }));
    return historiesWithDetails
        .fold<Map<String, ElectrumTransactionInfo>>(<String, ElectrumTransactionInfo>{}, (acc, tx) {
      if (tx == null) {
        return acc;
      }
      acc[tx.id] = acc[tx.id]?.updated(tx) ?? tx;
      return acc;
    });
  }

  Future<void> updateTransactions() async {
    try {
      if (_isTransactionUpdating) {
        return;
      }

      _isTransactionUpdating = true;
      final transactions = await fetchTransactions();
      transactionHistory.addMany(transactions);
      walletAddresses.updateReceiveAddresses();
      await transactionHistory.save();
      _isTransactionUpdating = false;
    } catch (e, stacktrace) {
      print(stacktrace);
      print(e);
      _isTransactionUpdating = false;
    }
  }

  void _subscribeForUpdates() {
    scriptHashes.forEach((sh) async {
      await _scripthashesUpdateSubject[sh]?.close();
      _scripthashesUpdateSubject[sh] = electrumClient.scripthashUpdate(sh);
      _scripthashesUpdateSubject[sh]?.listen((event) async {
        try {
          await updateUnspent();
          await updateBalance();
          await updateTransactions();
        } catch (e, s) {
          print(e.toString());
          _onError?.call(FlutterErrorDetails(
            exception: e,
            stack: s,
            library: this.runtimeType.toString(),
          ));
        }
      });
    });
  }

  Future<ElectrumBalance> _fetchBalances() async {
    final addresses = walletAddresses.addresses.toList();
    final balanceFutures = <Future<Map<String, dynamic>>>[];

    var totalConfirmed = 0;
    var totalUnconfirmed = 0;

    for (var i = 0; i < addresses.length; i++) {
      final addressRecord = addresses[i];
      final sh = scriptHash(addressRecord.address, networkType: networkType);
      final balanceFuture = electrumClient.getBalance(sh);
      balanceFutures.add(balanceFuture);
    }

    var totalFrozen = 0;
    unspentCoinsInfo.values.forEach((info) {
      unspentCoins.forEach((element) {
        if (element.hash == info.hash &&
            info.isFrozen &&
            element.address.address == info.address &&
            element.value == info.value) {
          totalFrozen += element.value;
        } else if (element.hash == info.hash &&
            element.isSilent &&
            element.address.address == info.address &&
            element.value == info.value) {
          totalConfirmed += element.value;
        }
      });
    });

    final balances = await Future.wait(balanceFutures);

    for (var i = 0; i < balances.length; i++) {
      final addressRecord = addresses[i];
      final balance = balances[i];
      final confirmed = balance['confirmed'] as int? ?? 0;
      final unconfirmed = balance['unconfirmed'] as int? ?? 0;
      totalConfirmed += confirmed;
      totalUnconfirmed += unconfirmed;

      if (confirmed > 0 || unconfirmed > 0) {
        addressRecord.setAsUsed();
      }
    }

    return ElectrumBalance(
        confirmed: totalConfirmed, unconfirmed: totalUnconfirmed, frozen: totalFrozen);
  }

  Future<void> updateBalance() async {
    balance[currency] = await _fetchBalances();
    await save();
  }

  String getChangeAddress() {
    const minCountOfHiddenAddresses = 5;
    final random = Random();
    var addresses = walletAddresses.addresses.where((addr) => addr.isHidden).toList();

    if (addresses.length < minCountOfHiddenAddresses) {
      addresses = walletAddresses.addresses.toList();
    }

    return addresses[random.nextInt(addresses.length)].address;
  }

  @override
  void setExceptionHandler(void Function(FlutterErrorDetails) onError) => _onError = onError;

  @override
  String signMessage(String message, {String? address = null}) {
    final index = address != null
        ? walletAddresses.addresses.firstWhere((element) => element.address == address).index
        : null;
    return index == null
        ? base64Encode(hd.sign(message))
        : base64Encode(hd.derive(index).sign(message));
  }
}
