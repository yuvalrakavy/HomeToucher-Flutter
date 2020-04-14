import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart'; 
import 'package:hometoucher/Model/homeToucherManagerService.dart';

export 'homeToucherManagerService.dart';

class HomeToucherModel {
  final SharedPreferences store;
  HomeToucherManagerServicesCollection homeToucherManagerServices;
  HomeToucherManagerService _defaultHomeToucherManagerService;

  HomeToucherModel(this.store) {
    homeToucherManagerServices = HomeToucherManagerServicesCollection(this);
  }

  static const String _defaultHomeToucherManagerServiceKey = "defaultHomeToucherManagerService";
  
  HomeToucherManagerService get defaultHomeToucherManagerService => store.containsKey(_defaultHomeToucherManagerServiceKey) ?
      _defaultHomeToucherManagerService ?? (_defaultHomeToucherManagerService = HomeToucherManagerService.fromJson(store.getString(_defaultHomeToucherManagerServiceKey))) : 
      null;
  
  set defaultHomeToucherManagerService(HomeToucherManagerService service) {
    _defaultHomeToucherManagerService = service;
    store.setString(_defaultHomeToucherManagerServiceKey, service.toJson());
  }

  static const String _useSpecificServerKey = "useSpecificServer";
  bool _hasUseSpecificServerValue = false;
  bool _useSpecificServer;

  bool get useSpecificServer {
    if(!_hasUseSpecificServerValue) {
      _useSpecificServer = store.getBool(_useSpecificServerKey);
      _hasUseSpecificServerValue = true;
    }

    return _useSpecificServer;
  }

  set useSpecificServer(bool value) {
    if(value != _useSpecificServer) {
      _useSpecificServer = value;
      store.setBool(_useSpecificServerKey, value);
    }      
  }

  static const String _specificServerAddressKey = "specificServerAddress";
  String _specificServerAddressJson;

  HomeToucherEndPoint get specificServerAddress => store.containsKey(_specificServerAddressKey) ?
    HomeToucherEndPoint.fromJson(_specificServerAddressJson ?? (_specificServerAddressJson = store.getString(_specificServerAddressKey)))
   : null;

  set specificServerAddress(HomeToucherEndPoint specificServerAddress) {
    if(specificServerAddress == null && _specificServerAddressJson != null) {
      _specificServerAddressJson = null;
      store.remove(_specificServerAddressKey);
    }
    else {
      final specificServerAddressJson = specificServerAddress.toJson();

      if(specificServerAddressJson != _specificServerAddressJson) {
        _specificServerAddressJson = specificServerAddressJson;
        store.setString(_specificServerAddressKey, specificServerAddressJson);
      }
    }
  }
}

class HomeToucherManagerServicesCollection  {
  final HomeToucherModel model;
  final Map<String, HomeToucherManagerService> map;

  static const String _homeToucherServicesKey = "homeToucherServices";

  HomeToucherManagerServicesCollection(this.model):
    map = _mapFromJsonObject(model.store);

  void update(HomeToucherManagerService service) {
      map[service.name] = service;

      model.store.setString(_homeToucherServicesKey, jsonEncode(toJsonObject()));
  }

  void remove(HomeToucherManagerService service) {
    if(map.containsKey(service.name)) {
      map.remove(service.name);
    }
    else
      print("Warning: remove of homeToucher Manager service ${service.name} that was not defined");
  }

  Iterable<HomeToucherManagerService> get list => map.values;

  dynamic toJsonObject() => List<dynamic>.unmodifiable(list.map((service) => service.toJsonObject()));

  static Map<String, HomeToucherManagerService> _mapFromJsonObject(SharedPreferences store) {
    if(store.containsKey(_homeToucherServicesKey)) {
      final jsonString = store.getString(_homeToucherServicesKey);
      final jsonObject = jsonDecode(jsonString);
      final Iterable<HomeToucherManagerService> services = jsonObject.map<HomeToucherManagerService>((jsonElement) => HomeToucherManagerService.fromJsonObject(jsonElement));
      final Iterable<String> names = services.map<String>((service) => service.name);

      return Map<String, HomeToucherManagerService>.fromIterables(names, services);
    }
    else
      return Map<String, HomeToucherManagerService>();
  }
}
