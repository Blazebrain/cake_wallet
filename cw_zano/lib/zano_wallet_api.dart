import 'dart:convert' as convert;
import 'dart:ffi';
import 'dart:isolate';

import 'package:cw_core/pathForWallet.dart';
import 'package:cw_core/transaction_priority.dart';
import 'package:cw_zano/api/consts.dart';
import 'package:cw_zano/api/model/asset_id_params.dart';
import 'package:cw_zano/api/model/create_wallet_result.dart';
import 'package:cw_zano/api/model/destination.dart';
import 'package:cw_zano/api/model/get_address_info_result.dart';
import 'package:cw_zano/api/model/get_recent_txs_and_info_params.dart';
import 'package:cw_zano/api/model/get_recent_txs_and_info_result.dart';
import 'package:cw_zano/api/model/get_wallet_info_result.dart';
import 'package:cw_zano/api/model/get_wallet_status_result.dart';
import 'package:cw_zano/api/model/proxy_to_daemon_params.dart';
import 'package:cw_zano/api/model/proxy_to_daemon_result.dart';
import 'package:cw_zano/api/model/store_result.dart';
import 'package:cw_zano/api/model/transfer.dart';
import 'package:cw_zano/api/model/transfer_params.dart';
import 'package:cw_zano/api/model/transfer_result.dart';
import 'package:cw_zano/model/zano_asset.dart';
import 'package:cw_zano/zano_wallet_exceptions.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:json_bigint/json_bigint.dart';
import 'package:monero/zano.dart' as zano;
import 'package:monero/src/generated_bindings_zano.g.dart' as zanoapi;

mixin ZanoWalletApi {
  static const _defaultNodeUri = '195.201.107.230:33336';
  static const _statusDelivered = 'delivered';
  static const _maxInvokeAttempts = 10;
  static const _maxReopenAttempts = 5;
  static const _logInfo = true;
  static const _logError = true;
  static const _logJson = false;
  static const int _zanoMixinValue = 10;

  int _hWallet = 0;

  int get hWallet => _hWallet;

  set hWallet(int value) {
    _hWallet = value;
  }

  int getCurrentTxFee(TransactionPriority priority) => zano.PlainWallet_getCurrentTxFee(priority.raw);

  String getOpenedWallets() => zano.PlainWallet_getOpenWallets();
  String getConnectivityStatus() => zano.PlainWallet_getConnectivityStatus();

  void setPassword(String password) => zano.PlainWallet_resetWalletPassword(hWallet, password);

  void closeWallet([int? walletToClose]) {
    info('close_wallet ${walletToClose ?? hWallet}');
    final result = zano.PlainWallet_closeWallet(walletToClose ?? hWallet);
    info('close_wallet result $result');
  }

  Future<bool> setupNode() async {
    info('init $_defaultNodeUri');
    // pathForWallet(name: , type: type)
    final result = zano.PlainWallet_init(_defaultNodeUri, "", 0);
    info('init result $result');
    return result == "OK";
  }

  Future<GetWalletInfoResult> getWalletInfo() async {
    final json = zano.PlainWallet_getWalletInfo(hWallet);
    final result = GetWalletInfoResult.fromJson(jsonDecode(json) as Map<String, dynamic>);
    _json('get_wallet_info', json);
    info('get_wallet_info got ${result.wi.balances.length} balances: ${result.wi.balances} seed: ${_shorten(result.wiExtended.seed)}');
    return result;
  }

  Future<GetWalletStatusResult> getWalletStatus() async {
    final json = zano.PlainWallet_getWalletStatus(hWallet);
    if (json == Consts.errorWalletWrongId) {
      error('wrong wallet id');
      throw ZanoWalletException('Wrong wallet id');
    }
    final status = GetWalletStatusResult.fromJson(jsonDecode(json) as Map<String, dynamic>);
    _json('get_wallet_status', json);
    if (_logInfo)
      info(
          'get_wallet_status connected: ${status.isDaemonConnected} in refresh: ${status.isInLongRefresh} progress: ${status.progress} wallet state: ${status.walletState}');
    return status;
  }

  Future<String> invokeMethod(String methodName, Object params) async {

    // var invokeResult = zano.PlainWallet_syncCall(
    //   'invoke', 
    //   hWallet, 
    //   jsonEncode(
    //     {
    //       "method": "$methodName",
    //       "params": params,
    //     },
    //   ),
    // );
    final request = jsonEncode({
      "method": methodName,
      "params": params,
    });
    print("zano: >>> $request");
    final invokeResult = zano.PlainWallet_syncCall(
      'invoke',
      hWallet,
      request,
    );
    print("zano: <<< ${invokeResult}");
    Map<String, dynamic> map;
    try {
      map = jsonDecode(invokeResult) as Map<String, dynamic>;
    } catch (e) {
      if (invokeResult.contains(Consts.errorWalletWrongId)) throw ZanoWalletException('Wrong wallet id');
      error('exception in parsing json in invokeMethod: $invokeResult');
      rethrow;
    }
    return invokeResult;
  }

  Future<List<ZanoAsset>> getAssetsWhitelist() async {
    try {
      final json = await invokeMethod('assets_whitelist_get', '{}');
      _json('assets_whitelist_get', json);
      final map = jsonDecode(json) as Map<String, dynamic>?;
      _checkForErrors(map);
      List<ZanoAsset> assets(String type, bool isGlobalWhitelist) =>
          (map?['result']?['result']?[type] as List<dynamic>?)
              ?.map((e) => ZanoAsset.fromJson(e as Map<String, dynamic>, isInGlobalWhitelist: isGlobalWhitelist))
              .toList() ??
          [];
      final localWhitelist = assets('local_whitelist', false);
      final globalWhitelist = assets('global_whitelist', true);
      final ownAssets = assets('own_assets', false);
      if (_logInfo)
        info('assets_whitelist_get got local whitelist: ${localWhitelist.length} ($localWhitelist); '
            'global whitelist: ${globalWhitelist.length} ($globalWhitelist); '
            'own assets: ${ownAssets.length} ($ownAssets)');
      return [...globalWhitelist, ...localWhitelist, ...ownAssets];
    } catch (e) {
      error('assets_whitelist_get $e');
      //return [];
      rethrow;
    }
  }

  Future<ZanoAsset?> addAssetsWhitelist(String assetId) async {
    try {
      final json = await invokeMethod('assets_whitelist_add', AssetIdParams(assetId: assetId));
      _json('assets_whitelist_add $assetId', json);
      final map = jsonDecode(json) as Map<String, dynamic>?;
      _checkForErrors(map);
      if (map!['result']!['result']!['status']! == 'OK') {
        final assetDescriptor = ZanoAsset.fromJson(map['result']!['result']!['asset_descriptor']! as Map<String, dynamic>);
        info('assets_whitelist_add added ${assetDescriptor.fullName} ${assetDescriptor.ticker}');
        return assetDescriptor;
      } else {
        info('assets_whitelist_add status ${map['result']!['result']!['status']!}');
        return null;
      }
    } catch (e) {
      error('assets_whitelist_add $e');
      return null;
    }
  }

  Future<bool> removeAssetsWhitelist(String assetId) async {
    try {
      final json = await invokeMethod('assets_whitelist_remove', AssetIdParams(assetId: assetId));
      _json('assets_whitelist_remove $assetId', json);
      final map = jsonDecode(json) as Map<String, dynamic>?;
      _checkForErrors(map);
      info('assets_whitelist_remove status ${map!['result']!['result']!['status']!}');
      return (map['result']!['result']!['status']! == 'OK');
    } catch (e) {
      error('assets_whitelist_remove $e');
      return false;
    }
  }

  Future<ProxyToDaemonResult?> _proxyToDaemon(String uri, String body) async {
    final json = await invokeMethod('proxy_to_daemon', ProxyToDaemonParams(body: body, uri: uri));
    final map = jsonDecode(json) as Map<String, dynamic>?;
    _checkForErrors(map);
    return ProxyToDaemonResult.fromJson(map!['result']['result'] as Map<String, dynamic>);
  }

  Future<ZanoAsset?> getAssetInfo(String assetId) async {
    final methodName = 'get_asset_info';
    final params = AssetIdParams(assetId: assetId);
    final result = await _proxyToDaemon('/json_rpc', '{"method": "$methodName","params": ${jsonEncode(params)}}');
    _json('$methodName $assetId', result?.body ?? '');
    if (result == null) {
      error('get_asset_info empty result');
      return null;
    }
    final map = jsonDecode(result.body) as Map<String, dynamic>?;
    if (map!['error'] != null) {
      info('get_asset_info $assetId error ${map['error']!['code']} ${map['error']!['message']}');
      return null;
    } else if (map['result']!['status']! == 'OK') {
      final assetDescriptor = ZanoAsset.fromJson(map['result']!['asset_descriptor']! as Map<String, dynamic>);
      info('get_asset_info $assetId ${assetDescriptor.fullName} ${assetDescriptor.ticker}');
      return assetDescriptor;
    } else {
      info('get_asset_info $assetId status ${map['result']!['status']!}');
      return null;
    }
  }

  Future<StoreResult?> store() async {
    try {
      final json = await invokeMethod('store', '{}');
      final map = jsonDecode(json) as Map<String, dynamic>?;
      _checkForErrors(map);
      return StoreResult.fromJson(map!['result']['result'] as Map<String, dynamic>);
    } catch (e) {
      error('store $e');
      return null;
    }
  }

  Future<GetRecentTxsAndInfoResult> getRecentTxsAndInfo({required int offset, required int count}) async {
    info('get_recent_txs_and_info $offset $count');
    try {
      final json = await invokeMethod('get_recent_txs_and_info', GetRecentTxsAndInfoParams(offset: offset, count: count));
      _json('get_recent_txs_and_info', json);
      final map = jsonDecode(json) as Map<String, dynamic>?;
      _checkForErrors(map);
      final lastItemIndex = map?['result']?['result']?['last_item_index'] as int?;
      final totalTransfers = map?['result']?['result']?['total_transfers'] as int?;
      final transfers = map?['result']?['result']?['transfers'] as List<dynamic>?;
      if (transfers == null || lastItemIndex == null || totalTransfers == null) {
        error('get_recent_txs_and_info empty transfers');
        return GetRecentTxsAndInfoResult.empty();
      }
      info('get_recent_txs_and_info transfers.length: ${transfers.length}');
      return GetRecentTxsAndInfoResult(
        transfers: transfers.map((e) => Transfer.fromJson(e as Map<String, dynamic>)).toList(),
        lastItemIndex: lastItemIndex,
        totalTransfers: totalTransfers,
      );
    } catch (e) {
      error('get_recent_txs_and_info $e');
      return GetRecentTxsAndInfoResult.empty();
    }
  }

  GetAddressInfoResult getAddressInfo(String address) => GetAddressInfoResult.fromJson(
        jsonDecode(zano.PlainWallet_getAddressInfo(address)) as Map<String, dynamic>,
      );

  String _shorten(String s) => s.length > 10 ? '${s.substring(0, 4)}...${s.substring(s.length - 4)}' : s;

  Future<CreateWalletResult> createWallet(String path, String password) async {
    info('create_wallet path $path password ${_shorten(password)}');
    final json = zano.PlainWallet_generate(path, password);
    _json('create_wallet', json);
    final map = jsonDecode(json) as Map<String, dynamic>?;
    if (map?['error'] != null) {
      final code = map!['error']!['code'] ?? '';
      final message = map['error']!['message'] ?? '';
      throw ZanoWalletException('Error creating wallet file, $message ($code)');
    }
    if (map?['result'] == null) {
      throw ZanoWalletException('Error creating wallet file, empty response');
    }
    final result = CreateWalletResult.fromJson(map!['result'] as Map<String, dynamic>);
    info('create_wallet ${result.name} ${result.seed}');
    return result;
  }

  Future<CreateWalletResult> restoreWalletFromSeed(String path, String password, String seed) async {
    info('restore_wallet path $path password ${_shorten(password)} seed ${_shorten(seed)}');
    final json = zano.PlainWallet_restore(seed, path, password, "");
    _json('restore_wallet', json);
    final map = jsonDecode(json) as Map<String, dynamic>?;
    if (map?['error'] != null) {
      final code = map!['error']!['code'] ?? '';
      final message = map['error']!['message'] ?? '';
      if (code == Consts.errorWrongSeed) {
        throw RestoreFromKeysException('Error restoring wallet, wrong seed');
      } else if (code == Consts.errorAlreadyExists) {
        throw RestoreFromKeysException('Error restoring wallet, already exists');
      }
      throw RestoreFromKeysException('Error restoring wallet, $message ($code)');
    }
    if (map?['result'] == null) {
      throw RestoreFromKeysException('Error restoring wallet, empty response');
    }
    final result = CreateWalletResult.fromJson(map!['result'] as Map<String, dynamic>);
    info('restore_wallet ${result.name} ${result.wi.address}');
    return result;
  }

  Future<CreateWalletResult> loadWallet(String path, String password, [int attempt = 0]) async {
    info('load_wallet1 path $path password ${_shorten(password)}');
    final String json;
    try {
      json = zano.PlainWallet_open(path, password);
    } catch (e) {
      error('error in loadingWallet $e'); 
      rethrow;
    }
    info('load_wallet2: $json');
    final map = jsonDecode(json) as Map<String, dynamic>?;
    if (map?['error'] != null) {
      final code = map?['error']!['code'] ?? '';
      final message = map?['error']!['message'] ?? '';
      if (code == Consts.errorAlreadyExists && attempt <= _maxReopenAttempts) {
        // already connected to this wallet. closing and trying to reopen
        info('already connected. closing and reopen wallet (attempt $attempt)');
        closeWallet(attempt);
        await Future.delayed(const Duration(milliseconds: 500));
        return await loadWallet(path, password, attempt + 1);
      }
      throw ZanoWalletException('Error loading wallet, $message ($code)');
    }
    if (map?['result'] == null) {
      throw ZanoWalletException('Error loading wallet, empty response');
    }
    final result = CreateWalletResult.fromJson(map!['result'] as Map<String, dynamic>);
    info('load_wallet3 ${result.name} ${result.wi.address}');
    zano.PlainWallet_init(_defaultNodeUri, path, 0);
    return result;
  }

  Future<TransferResult> transfer(List<Destination> destinations, BigInt fee, String comment) async {
    final params = TransferParams(
      destinations: destinations,
      fee: fee,
      mixin: _zanoMixinValue,
      paymentId: '',
      comment: comment,
      pushPayer: false,
      hideReceiver: true,
    );
    final json = await invokeMethod('transfer', params);
    _json('transfer', json);
    final map = jsonDecode(json);
    final resultMap = map['result'] as Map<String, dynamic>?;
    if (resultMap != null) {
      final transferResultMap = resultMap['result'] as Map<String, dynamic>?;
      if (transferResultMap != null) {
        final transferResult = TransferResult.fromJson(transferResultMap);
        info('transfer success hash ${transferResult.txHash}');
        return transferResult;
      } else {
        final errorCode = resultMap['error']['code'];
        final code = errorCode is int ? errorCode.toString() : errorCode as String? ?? '';
        final message = resultMap['error']['message'] as String? ?? '';
        error('transfer error $code $message');
        throw TransferException('Transfer error, $message ($code)');
      }
    }
    error('transfer error empty result');
    throw TransferException('Transfer error, empty result');
  }

  void _checkForErrors(Map<String, dynamic>? map) {
    if (map == null) {
      throw ZanoWalletException('Empty response');
    }
    final result = map['result'];
    if (result == null) {
      throw ZanoWalletException('Empty response');
    }
    if (result['error'] != null) {
      final code = result['error']!['code'] ?? '';
      final message = result['error']!['message'] ?? '';
      if (code == -1 && message == Consts.errorBusy) {
        throw ZanoWalletBusyException();
      }
      throw ZanoWalletException('Error, $message ($code)');
    }
  }

  /*Future<void> _writeLog(String method, String logMessage) async {
    final dir = await getDownloadsDirectory();
    final logFile = File('${dir!.path}/$method.txt');
    final date = DateTime.now();
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    String removeCRandLF(String input) => input.replaceAll(RegExp('\r|\n'), '');
    await logFile.writeAsString('${twoDigits(date.hour)}:${twoDigits(date.minute)}:${twoDigits(date.second)} ${removeCRandLF(logMessage)}\n',
        mode: FileMode.append);
  }*/

  static void info(String s) => _logInfo ? debugPrint('[info] $s') : null;
  static void error(String s) => _logError ? debugPrint('[error] $s') : null;
  static void printWrapped(String text) => RegExp('.{1,800}').allMatches(text).map((m) => m.group(0)).forEach(print);
  static void _json(String methodName, String json) => _logJson ? printWrapped('$methodName $json') : null;
  
  Map<String, dynamic> jsonDecode(String json) {
    try {
      return decodeJson(json.replaceAll("\\/", "/")) as Map<String, dynamic>;
    } catch (e) {
      return convert.jsonDecode(json) as Map<String, dynamic>;
    }
  }

  String jsonEncode(Object? object) {
    return convert.jsonEncode(object);
  }
}
