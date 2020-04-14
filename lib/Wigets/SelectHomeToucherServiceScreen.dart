import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
import 'package:hometoucher/Model/model.dart';
import 'package:mdns_plugin/mdns_plugin.dart';
import 'package:hometoucher/RFB/sessionSetup.dart';

typedef void HomeToucherManagerSelected();

class HomeToucherManagerServiceListStateEntry {
  final HomeToucherManagerServiceListState serviceListState;
  bool isLocated;
  HomeToucherManagerService service; // Reference to the service in the model

  HomeToucherManagerServiceListStateEntry(this.serviceListState, this.service,
      {this.isLocated = false});

  bool get isSelected => serviceListState.isSelected(this);

  void located(HomeToucherManagerService homeToucherManagerService) {
    assert(homeToucherManagerService.name == service.name);
    service = homeToucherManagerService;
    isLocated = true;
  }
}

class HomeToucherManagerServiceListState extends ChangeNotifier
    implements MDNSPluginDelegate {
  final HomeToucherModel model;
  final HomeToucherManagerSelected onHomeToucherManagerServiceSelected;
  bool shouldReconnect = false;

  final _map = <String, HomeToucherManagerServiceListStateEntry>{};
  String _selectedHomeToucherManagerServiceName;
  List<HomeToucherManagerServiceListStateEntry> _list;

  HomeToucherManagerServiceListState({@required this.model, this.onHomeToucherManagerServiceSelected}) {
    for (final service in model.homeToucherManagerServices.list) {
      _map[service.name] =
          HomeToucherManagerServiceListStateEntry(this, service);
    }

    _selectedHomeToucherManagerServiceName =
        model.defaultHomeToucherManagerService?.name;
  }

  List<HomeToucherManagerServiceListStateEntry> get list {
    List<HomeToucherManagerServiceListStateEntry> generateList() {
      final list = _map.values.toList();

      list.sort((e1, e2) => e1.service.name.compareTo(e2.service.name));
      return list;
    }

    return _list ?? (_list = generateList());
  }

  Future<void> locateHomeToucherManagerServices(
      {locateProcessDuration = const Duration(seconds: 2)}) async {
    final mdns = MDNSPlugin(this);

    await mdns.startDiscovery(
        HomeToucherManagerServiceLocator.HomeToucherManagerServiceMdnsType);
    await Future.delayed(locateProcessDuration);
    await mdns.stopDiscovery();
  }

  bool isSelected(HomeToucherManagerServiceListStateEntry listEntry) =>
      _selectedHomeToucherManagerServiceName != null &&
      _selectedHomeToucherManagerServiceName == listEntry.service.name;

  void onSelectEntry(HomeToucherManagerServiceListStateEntry listEntry) {
    _selectedHomeToucherManagerServiceName = listEntry.service.name;
    model.defaultHomeToucherManagerService = listEntry.service;
    shouldReconnect = true;

    onHomeToucherManagerServiceSelected?.call();

    notifyListeners();
  }

  void onRemoveEntry(HomeToucherManagerServiceListStateEntry listEntry) {
    assert(listEntry.isLocated ==
        false); // Should not be able to remove located entries
    model.homeToucherManagerServices.remove(listEntry.service);
    _map.remove(listEntry.service.name);
    _list = null;
    notifyListeners();
  }

  @override
  void onDiscoveryStarted() {}
  @override
  void onDiscoveryStopped() {}
  @override
  bool onServiceFound(MDNSService service) => true;
  @override
  void onServiceUpdated(MDNSService service) {}

  @override
  void onServiceRemoved(MDNSService service) {
    final entry = _map[service.name];

    if (entry != null) {
      entry.isLocated = false;
      notifyListeners();
    }
  }

  @override
  void onServiceResolved(MDNSService service) {
    //if(service.name == 'Tel-Aviv')
    //  return;     //DEBUG

    final homeToucherManagerService =
        HomeToucherManagerService.fromMDNSService(service);
    final entry = _map[homeToucherManagerService.name];

    model.homeToucherManagerServices.update(homeToucherManagerService);

    if (entry != null)
      entry.located(homeToucherManagerService);
    else {
      _map[homeToucherManagerService.name] =
          HomeToucherManagerServiceListStateEntry(
              this, homeToucherManagerService,
              isLocated: true);
      _list = null; // New item added - force rebuilding the list
    }

    notifyListeners();
  }
}

class SelectHomeToucherManagerServiceScreen extends StatelessWidget {
  final HomeToucherModel model;
  final HomeToucherManagerSelected onHomeToucherManagerServiceSelected;

  SelectHomeToucherManagerServiceScreen({@required this.model, this.onHomeToucherManagerServiceSelected});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<HomeToucherManagerServiceListState>(
      create: (_) {
        final state = HomeToucherManagerServiceListState(model: model, onHomeToucherManagerServiceSelected: onHomeToucherManagerServiceSelected);

        state.locateHomeToucherManagerServices();
        return state;
      },

      child: SafeArea(
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Select HomeToucher Service'),
          ),
          body: Consumer<HomeToucherManagerServiceListState>(
            builder: (context, listState, child) {
              if(listState.list.length == 0) {
                return Center(
                  child: Text("No HomeToucher services found.\nMake sure that you are connected to the correct network.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold
                  ))
                );
              }
              else {
                return ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(8),
                  children: <Widget>[
                    TitleEntry(title: "Please select HomeToucher service:"),
                    for (var entry in listState.list)
                      if(entry.isLocated)
                        LocatedHomeToucherManagerServiceListEntry(entry)
                      else
                        NotLocatedHomeToucherManagerServiceListEntry(entry)
                  ],
                );
              }
            }
          )
        ),
      )
    );
  }
}

class TitleEntry extends StatelessWidget {
  final String title;

  TitleEntry({@required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text("$title",
            style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.bold
            ),
          )
        )
      )
    );
  }
}

class LocatedHomeToucherManagerServiceListEntry extends StatelessWidget {
  final HomeToucherManagerServiceListStateEntry entry;

  LocatedHomeToucherManagerServiceListEntry(this.entry);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(
          entry.service.name,
          style: TextStyle(
              color: entry.isLocated
                  ? (entry.isSelected
                      ? Theme.of(context).primaryColor
                      : Theme.of(context).textTheme.bodyText1.color)
                  : Colors.grey),
        ),
        leading: SizedBox(
            width: 20,
            child: entry.isSelected ? Icon(Icons.check) : Container()),
        selected: entry.isSelected,
        onTap: () => entry.serviceListState.onSelectEntry(entry),
      ),
    );
  }
}

class NotLocatedHomeToucherManagerServiceListEntry extends LocatedHomeToucherManagerServiceListEntry {
  NotLocatedHomeToucherManagerServiceListEntry(HomeToucherManagerServiceListStateEntry entry) : super(entry);

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: UniqueKey(),
      child: super.build(context),
      onDismissed: (direction) => entry.serviceListState.onRemoveEntry(entry),
    );
  }
}
