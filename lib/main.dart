import 'dart:async';
import 'dart:io';

import 'package:hometoucher/RFB/RemoteScreenController.dart';
import 'package:hometoucher/Wigets/SelectHomeToucherServiceScreen.dart';
import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hometoucher/Model/model.dart';
import 'package:hometoucher/Wigets/RemoteScreen.dart';
import 'package:hometoucher/RFB/sessionSetup.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(
      [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  await SystemChrome.setEnabledSystemUIOverlays([]);

  final store = await SharedPreferences.getInstance();
  runApp(MyApp(store));
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  final SharedPreferences store;

  MyApp(this.store);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'HomeToucher',
        theme: ThemeData(
          // This is the theme of your application.
          //
          // Try running your application with "flutter run". You'll see the
          // application has a blue toolbar. Then, without quitting the app, try
          // changing the primarySwatch below to Colors.green and then invoke
          // "hot reload" (press "r" in the console where you ran "flutter run",
          // or simply save your changes to "hot reload" in a Flutter IDE).
          // Notice that the counter didn't reset back to zero; the application
          // is not restarted.
          primarySwatch: Colors.blue,
        ),
        home: ChangeNotifierProvider<HomeToucherController>(
            create: (_) =>
                HomeToucherController(model: HomeToucherModel(store)),
            child: HomeToucherScreen()));
  }
}

class HomeToucherScreen extends StatelessWidget {
  Widget build(BuildContext context) {
    void startHomeToucherController() {
      final homeToucherController =
          Provider.of<HomeToucherController>(context, listen: false);

      homeToucherController.run(mediaQueryData: MediaQuery.of(context));
    }

    startHomeToucherController();

    return Consumer<HomeToucherController>(
        builder: (context, homeToucherController, _) {
      switch (homeToucherController.state) {
        case HomeToucherState.initializing:
          return Scaffold(body: Container());

        case HomeToucherState.connecting:
          return ChangeNotifierProvider<SessionCreationState>.value(
            value: homeToucherController.sessionCreationState,
            child: ConnectionInProgressScreen(homeToucherController),
          );

        case HomeToucherState.connected:
          return RemoteScreenSession(
              homeToucherController: homeToucherController);

        case HomeToucherState.mustSelectHomeToucherManagerService:
          return SelectHomeToucherManagerServiceScreen(
              model: homeToucherController.model,
              onHomeToucherManagerServiceSelected: () =>
                  homeToucherController.retryToConnect());

        default:
          print("Unsupported state ${homeToucherController.state}");
          return Center(
              child: Text("E R R O R: ${homeToucherController.state}"));
      }
    });
  }
}

class ConnectionInProgressScreen extends StatelessWidget {
  final HomeToucherController homeToucherState;

  ConnectionInProgressScreen(this.homeToucherState);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<SessionCreationState>(
          builder: (context, sessionCreationState, _) => Center(
            child: GestureDetector(
              child: Text(sessionCreationState.connectionStateDescription,
                style: TextStyle(fontSize: 20)
              ),
              onScaleEnd: (details) {
                final homeToucherController = Provider.of<HomeToucherController>(context, listen: false);

                homeToucherController.cancelConnect();
              },
            )
          )
      ),
    );
  }
}

class SessionCreationState extends ChangeNotifier {
  RFBsessionState _connectionState;

  RFBsessionState get connectionState => _connectionState;

  set connectionState(RFBsessionState newState) {
    _connectionState = newState;
    notifyListeners();
  }

  String get connectionStateDescription {
    switch (connectionState) {
      case RFBsessionState.HomeToucherManagerLookup:
        return "Looging for HomeToucher Manager service";
      case RFBsessionState.HomeToucherManagerNotFound:
        return "Could not locate any HomeToucher Manager service";
      case RFBsessionState.RFBserverLookup:
        return "Looking for HomeToucher server";
      case RFBsessionState.RFBserverCouldNotBeConnected:
        return "Could not find suitable HomeToucher server";
      case RFBsessionState.ConnectingToRFBserver:
        return "Connecting to HomeToucher server";
      case RFBsessionState.Connected:
        return "Connected";
      case RFBsessionState.Canceled:
        return "Connection has been canceled";
      default:
        return "Unknown state $connectionState";
    }
  }
}

enum HomeToucherState {
  initializing,
  connecting,
  connected,
  mustSelectHomeToucherManagerService
}

class HomeToucherController extends ChangeNotifier {
  final HomeToucherModel model;

  HomeToucherController({@required this.model});

  MediaQueryData mediaQueryData;
  RFBsessionSetup sessionSetup;
  RemoteScreenController _remoteScreenController;
  SessionCreationState _sessionCreationState;
  Completer<void> _retryConnectCompleter;

  get sessionCreationState => _sessionCreationState;
  get remoteScreenController => _remoteScreenController;

  HomeToucherState _state = HomeToucherState.initializing;

  set state(HomeToucherState newState) {
    print("HomeToucherState: set State to $newState");
    this._state = newState;
    notifyListeners();
  }

  get state => _state;

  Future<void> run({@required MediaQueryData mediaQueryData}) async {
    this.mediaQueryData = mediaQueryData;

    // This delay is to ensure that the code is executed not within the context of the 'build' function
    // that calls run().
    //
    // (This is due to the fact that setting state cause notifyListenrs to be called, and since this will cause its consumer to be rebuild
    // it causes an invalid build inside a build which causes flutter to throw an exception)
    //
    await Future.delayed(Duration(milliseconds: 10));

    while (true) {
      final socket = await _connect();

      if (socket != null)
        await _runSession(socket);
      else {
        _retryConnectCompleter = Completer<void>();
        state = HomeToucherState.mustSelectHomeToucherManagerService;
        await _retryConnectCompleter.future;
      }
    }
  }

  Future<Socket> _connect() async {
    _sessionCreationState = SessionCreationState();
    final sessionSetup = RFBsessionSetup(
      mediaQueryData: mediaQueryData,
      onStatusUpdate: (state) => _sessionCreationState.connectionState = state,
      onUpdateDefaultHomeToucherManagerService: (service) =>
          model.defaultHomeToucherManagerService = service,
      defaultHomeToucherManagerService: model.defaultHomeToucherManagerService,
      onFoundHomeToucherManagerService: (service) =>
          model.homeToucherManagerServices.update(service),
    );

    state = HomeToucherState.connecting;

    try {
      final socket = await sessionSetup.createSession();

      return socket;
    } catch (e) {
      print("sessionSetup failed with $e");
      return null;
    } finally {
      _sessionCreationState = null;
    }
  }

  Future<void> _runSession(Socket socket) async {
    _remoteScreenController = RemoteScreenController(
        deviceSizeInPixels:
            mediaQueryData.size * mediaQueryData.devicePixelRatio,
        socket: socket);

    state = HomeToucherState.connected;

    try {
      await _remoteScreenController.generateFrames();
    } catch (e) {
      print("remoteScreenController generate frame exception $e");
    } finally {
      _remoteScreenController = null;
      socket.close();
    }
  }

  void restartSession() {
    switch (state) {
      case HomeToucherState.connected:
        assert(remoteScreenController != null);
        remoteScreenController.terminate();
        break;
    }
  }

  Future<void> cancelConnect() async {
    if(sessionSetup != null) {
      await sessionSetup.cancel();
      state = HomeToucherState.mustSelectHomeToucherManagerService;
    }
  }

  void retryToConnect() {
    assert(_retryConnectCompleter != null);
    _retryConnectCompleter.complete();
    _retryConnectCompleter = null;
  }
}
