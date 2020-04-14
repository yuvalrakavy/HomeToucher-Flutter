
import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:async/async.dart';
import 'package:flutter/material.dart';
import 'package:hometoucher/Model/model.dart';
import 'package:udp/udp.dart';
import 'package:mdns_plugin/mdns_plugin.dart';
import 'package:device_info/device_info.dart';

enum RFBsessionState {
  HomeToucherManagerLookup,
  HomeToucherManagerNotFound,
  RFBserverLookup,
  ConnectingToRFBserver,
  RFBserverCouldNotBeConnected,
  Connected,
  Canceled,
}

typedef void OnStatusUpdateFunc(RFBsessionState staus);
typedef void OnSetHomeToucherManagerFunc(HomeToucherManagerService homeToucherManagerService);
typedef void SetOperationFunc(CancelableOperation operation);

class NoHomeToucherManagerServiceFound implements Exception { }
class AmbigiousHomeToucherManagerServices implements Exception { }
class HometoucherQueryFailed implements Exception { }
class ConnectionToRFBserverFailed implements Exception { }

class RFBsessionSetup {
  final HomeToucherManagerService defaultHomeToucherManagerService;
  final RFBserverAddress specificServer;
  CancelableOperation operation;
  final Duration defaultDurationBeteenRetry;
  final Duration connectTimeout;
  final OnStatusUpdateFunc onStatusUpdate;
  final OnSetHomeToucherManagerFunc onUpdateDefaultHomeToucherManagerService;
  final OnSetHomeToucherManagerFunc onFoundHomeToucherManagerService;
  final MediaQueryData mediaQueryData;

  RFBsessionSetup({
    @required this.mediaQueryData,
    this.defaultHomeToucherManagerService, 
    this.specificServer,
    this.onStatusUpdate,
    this.defaultDurationBeteenRetry = const Duration(seconds: 5),
    this.connectTimeout = const Duration(seconds: 2),
    this.onUpdateDefaultHomeToucherManagerService,
    this.onFoundHomeToucherManagerService,
  });

  // Create session with RFB server.
  //  This function will keep trying to estabish a session until one is created. It will throw an exception only
  //  if the HomeToucher manager service to be used is ambigious. In this case, the caller should prompt the user
  //  and retry with the selected service as the defaultTouchManagerService
  //
  // returns
  //  Socket - valid socket to be used for the RFB session
  //  null - the operation was aborted
  //
  // Throws an exception:
  //  AmbigiousHomeToucherManagerServices - The user must select the home toucher service to be used
  //
  Future<Socket> createSession() async {

    if(specificServer != null) {
      return _connectToServer(specificServer);
    }
    else {
      RFBserverAddress serverAddress;
      var homeToucherManagerService = defaultHomeToucherManagerService;
      Duration durationBetweenRetries;

      while(true) {
        try {
          if(serverAddress != null) {
            print("Attempt to connect to $serverAddress");
            // Return either valid socket or null (if operation was aborted)
            print("Calling _connectToServer");
            return await _connectToServer(serverAddress, maxRetries: 1);
          }
        } catch(e) {
          print("_ConnectToServer failed $serverAddress failed - $e");
          serverAddress = null;
        }

        if(homeToucherManagerService != null) {
          try {
            print("Attempt query $homeToucherManagerService for RFB server address");
            final queryHomeToucherService = QueryHometoucherManagerService(
              mediaQueryData: mediaQueryData,
              homeToucherManagerService: homeToucherManagerService,
              setCancelableOperation: (op) => operation = op
            );

            onStatusUpdate?.call(RFBsessionState.RFBserverLookup);
            serverAddress = await queryHomeToucherService.query();

            if(serverAddress == null) {
              onStatusUpdate?.call(RFBsessionState.Canceled);
              return null;      // Operation aborted
            }
          }
          on HometoucherQueryFailed {
            print("Query HomeToucher Manager service at $homeToucherManagerService failed");
            homeToucherManagerService = null;
          }
        }

        if(homeToucherManagerService == null) {
          try {
            print("Attempt to locate HomeToucher manager service");
            final homeToucherManagerServiceLocator = HomeToucherManagerServiceLocator(
              lastUsedDomainName: defaultHomeToucherManagerService?.name,
               setOperation: (op) => operation = op,
               onFoundHomeTouchManagerService: onFoundHomeToucherManagerService
            );

            onStatusUpdate?.call(RFBsessionState.HomeToucherManagerLookup);
            homeToucherManagerService = await homeToucherManagerServiceLocator.locate();

            if(homeToucherManagerService == null) {
              onStatusUpdate?.call(RFBsessionState.Canceled);
              return null;
            }
            else {
              onUpdateDefaultHomeToucherManagerService?.call(homeToucherManagerService);
            }
          }
          on AmbigiousHomeToucherManagerServices {
            rethrow;
          }
          catch (e) {
            print("Could not locate HomeToucher Manager service ($e)");
          }
        }

        // The first time getting here, no waiting will be done
        if(durationBetweenRetries != null) {
          print("Waiting between retries");
          if(await _waitBetweenRetries(durationBetweenRetries))
            return null;      // Operation was canceled
          print("Waiting done");
        }
        else
          durationBetweenRetries = defaultDurationBeteenRetry;    // If get to this point again, wait

      }
    }
  }

  // Cancel pending operation - will cause createSession to return null
  Future<void> cancel() async =>  await operation?.cancel();

  // connect to server with a given address
  //
  //  returns:
  //   valid socket if connection is successful
  //   null if operation was aborted
  //
  //  throw an exception if connection was not successful after maxRetries
  //
  Future<Socket> _connectToServer(RFBserverAddress server, {int maxRetries = 0}) async {
    for(int retryCount = 0; maxRetries == 0 || retryCount < maxRetries; retryCount++) {
      try {
        onStatusUpdate?.call(RFBsessionState.ConnectingToRFBserver);
        operation = CancelableOperation.fromFuture(Socket.connect(server.address, server.port, timeout: connectTimeout));

        final socket = await operation.valueOrCancellation(null);

        operation = null;
        onStatusUpdate?.call(socket != null ? RFBsessionState.Connected : RFBsessionState.Canceled);
        return socket;    // Valid socket or null if operation was aborted
      }
      catch(e) {
        print('Connecting to server $server failed: $e');
        onStatusUpdate?.call(RFBsessionState.RFBserverCouldNotBeConnected);
      }

      if(maxRetries == 0 || retryCount != maxRetries-1) {
        if(await _waitBetweenRetries(defaultDurationBeteenRetry))
          return null;
      }
    }

    return Future.error(ConnectionToRFBserverFailed());
  }

  Future<bool> _waitBetweenRetries(Duration waitPeriod) async {
    operation = CancelableOperation.fromFuture(Future.delayed(defaultDurationBeteenRetry));
    await operation.valueOrCancellation();
    final isCanceled = operation.isCanceled;
    operation = null;

    return isCanceled;
  }

}

class RFBserverAddress {
  final InternetAddress address;
  final int port;

  RFBserverAddress(this.address, this.port);

  @override String toString() => "$address:$port";
}

class HomeToucherManagerServiceLocator implements MDNSPluginDelegate {
  final String lastUsedDomainName;
  final SetOperationFunc setOperation;
  final OnSetHomeToucherManagerFunc onFoundHomeTouchManagerService;
  static const String HomeToucherManagerServiceMdnsType = "_HtVncConf._udp.";

  HomeToucherManagerService _actualLastUsedHomeToucherManagerService; // Not null if name is the same as the last used domain
  HomeToucherManagerService _actualNearestHomeToucherManagerService;
  HomeToucherManagerService _actualLocatedHomeToucherManagerService;
  int _domainsCount;
  
  HomeToucherManagerServiceLocator({this.lastUsedDomainName, this.setOperation, this.onFoundHomeTouchManagerService});

  Future<HomeToucherManagerService> locate({Duration timeout = const Duration(seconds: 1)}) async {
    var mDnsPlugin = MDNSPlugin(this);

    await mDnsPlugin.startDiscovery(HomeToucherManagerServiceMdnsType);
    final operation = CancelableOperation.fromFuture(Future.delayed(timeout, () => false));

    setOperation?.call(operation);
    bool aborted = await operation.valueOrCancellation(true);
    setOperation?.call(null);

    if(aborted)
      return null;
    
    await mDnsPlugin.stopDiscovery();

    if(_actualNearestHomeToucherManagerService != null)
      return _actualLastUsedHomeToucherManagerService;
    else if(_actualLastUsedHomeToucherManagerService != null)
      return _actualLastUsedHomeToucherManagerService;
    else if(_domainsCount == 1 && _actualLocatedHomeToucherManagerService != null)
      return _actualLocatedHomeToucherManagerService;
    else if(_domainsCount == 0)
      throw NoHomeToucherManagerServiceFound();
    else
      throw AmbigiousHomeToucherManagerServices();
  }

  bool _isNearby(MDNSService service) {
    return false;
  }

  // MDNSPluginDelegate implementaion

  @override  void onDiscoveryStarted() {
    _domainsCount = 0;
  }

  @override  void onDiscoveryStopped() {  }
  @override  bool onServiceFound(MDNSService service) => true;
  @override  void onServiceRemoved(MDNSService service) {  }

  @override  void onServiceResolved(MDNSService service) {
    final homeToucherManagerService = HomeToucherManagerService.fromMDNSService(service);
    print('service resolve $service');

    onFoundHomeTouchManagerService?.call(homeToucherManagerService);

    if(lastUsedDomainName != null && lastUsedDomainName == service.name)
      _actualLastUsedHomeToucherManagerService = homeToucherManagerService;

    if(_isNearby(service))
      _actualNearestHomeToucherManagerService = homeToucherManagerService;

    _actualLocatedHomeToucherManagerService = homeToucherManagerService;
    _domainsCount++;
  }

  @override  void onServiceUpdated(MDNSService service) {  }
}

class QueryHometoucherManagerService {
  final HomeToucherManagerService homeToucherManagerService;
  final SetOperationFunc setCancelableOperation;
  final MediaQueryData mediaQueryData;

  QueryHometoucherManagerService({
    @required this.homeToucherManagerService,
    @required this.mediaQueryData,
    this.setCancelableOperation,
  });

  Future<Map<String, String>> _buildQuery() async {
    final s = (x) => x.toInt().toString();
    final deviceInfo = DeviceInfoPlugin();
    String name;

    if(Platform.isIOS) {
      final iosDeviceInfo = await deviceInfo.iosInfo;

      name = iosDeviceInfo.name;
    }
    else if(Platform.isAndroid) {
      final androidDeviceInfo = await deviceInfo.androidInfo;

      name = "Android-${androidDeviceInfo.androidId}-${androidDeviceInfo.device}";
    }
    else
      name = Platform.localHostname;
    
    final query = {
        'Name': name,
        'ScreenWidth': s(mediaQueryData.size.width * mediaQueryData.devicePixelRatio),
        'ScreenHeight': s(mediaQueryData.size.height * mediaQueryData.devicePixelRatio),
        'SafeTop': s(mediaQueryData.padding.top * mediaQueryData.devicePixelRatio),
        'SafeBottom': s(mediaQueryData.padding.bottom * mediaQueryData.devicePixelRatio),
        'SafeRight': s(mediaQueryData.padding.right * mediaQueryData.devicePixelRatio),
        'SafeLeft': s(mediaQueryData.padding.left * mediaQueryData.devicePixelRatio),
        'FormFactor': 'iPhone',
    };

    return query;
  } 

  //
  // query HomeToucher manager service for the RFB server to connect to.
  //
  // Returns:
  //  RFBserverAddress - (IP address/port) address of RFB server to connect to
  //  null - operation was aborted
  //
  // throws an exception in case on an error
  //
  Future<RFBserverAddress> query({timeout = const Duration(milliseconds: 2000), retries = 2}) async {
    final query = await _buildQuery();
    final queryData = _buildQueryData(query);
    final localEndpoint = Endpoint.any();
    final hometoucherManagerEndpoint = Endpoint.unicast(homeToucherManagerService.endPoint.address, port: homeToucherManagerService.endPoint.port);

    for(var retryCount = 0; retryCount < retries; retryCount++) {
      try {
        final udp = await UDP.bind(localEndpoint);
        final queryRepliedCompleter = Completer<List<int>>();
        final queryRepliedFuture = queryRepliedCompleter.future;

        await udp.send(queryData, hometoucherManagerEndpoint);
        await udp.listen((datagram) => queryRepliedCompleter.complete(datagram.data));

        final operation = CancelableOperation.fromFuture(queryRepliedFuture.timeout(timeout));
        setCancelableOperation?.call(operation);

        final queryResultData = await operation.valueOrCancellation(null);
        setCancelableOperation?.call(null);

        if(queryResultData == null)
          return null;        // Operation was abored

        final queryResult = _parseQueryResultData(queryResultData);

        return RFBserverAddress(InternetAddress(queryResult['Server']), int.parse(queryResult['Port']));
      } catch(e) {
        print('Retry: $retryCount: $e service ${homeToucherManagerService.endPoint.address}:${homeToucherManagerService.endPoint.port}');
      }
    }

    throw HometoucherQueryFailed();
  }

  List<int> _buildQueryData(Map<String, String> fields) {
    var query  = List<int>();

    void addValue(String value) {
      final data = utf8.encode(value);
      final count = data.length;

      query.add(count >> 8);
      query.add(count & 0xff);
      query.addAll(data);
    }

    for (var nameValuePair in fields.entries) {
      addValue(nameValuePair.key);
      addValue(nameValuePair.value);
    }

    addValue("");
    addValue("");

    return query;
  }

  Map<String, String> _parseQueryResultData(List<int>rawData) {
    var queryResult = Map<String, String>();
    var p = 0;

    String getNextValue() {
      final length = (rawData[p] << 8) | (rawData[p+1] & 0xff);

      p += 2;
      final value = utf8.decode(rawData.sublist(p, p + length));
      p += length;

      return value;
    }

    while(true) {
      final name = getNextValue();

      if(name.isEmpty)
        break;

      final value = getNextValue();
      queryResult[name] = value;
    }

    return queryResult;
  }
}