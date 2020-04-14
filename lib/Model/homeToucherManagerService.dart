
import 'dart:io';
import 'dart:convert';
import 'dart:math' show cos, sqrt, asin;

import 'package:meta/meta.dart';
import 'package:mdns_plugin/mdns_plugin.dart';
import 'package:udp/udp.dart';

class HomeToucherManagerService {
  final String name;
  final HomeToucherEndPoint endPoint;

  final HomeToucherLocation location;

  HomeToucherManagerService({@required this.name, @required this.endPoint, this.location});

  HomeToucherManagerService.fromMDNSService(MDNSService service) :
    name = service.name,
    endPoint = HomeToucherEndPoint.fromService(service),
    location = HomeToucherLocation.fromService(service)
  ;

  HomeToucherManagerService.fromJsonObject(Map<dynamic, dynamic> jsonObject) :  
    name = jsonObject['name'],
    endPoint = HomeToucherEndPoint.fromJsonObject(jsonObject),
    location = HomeToucherLocation.fromJsonObject(jsonObject);

  factory HomeToucherManagerService.fromJson(String json) => HomeToucherManagerService.fromJsonObject(jsonDecode(json));

  Map<String, dynamic> toJsonObject() {
    final map = {
      'name': name,
    };

    map.addAll(endPoint.toJsonObject());

    if(location != null)
      map.addAll(location.toJsonObject());

    return map;
  }

  String toJson() => jsonEncode(toJsonObject());
}

class HomeToucherEndPoint {
  final InternetAddress address;
  final Port port;

  HomeToucherEndPoint({@required this.address, @required this.port});

  HomeToucherEndPoint.fromJsonObject(Map<String, dynamic> jsonObject) :
    address = InternetAddress(jsonObject["address"]), port = Port(int.parse(jsonObject["port"])); 

  factory HomeToucherEndPoint.fromJson(String json) => HomeToucherEndPoint.fromJson(jsonDecode(json));

  factory HomeToucherEndPoint.fromService(MDNSService service) => HomeToucherEndPoint(
    address: InternetAddress(service.addresses.firstWhere((String s) => s.contains('.'), orElse: () => service.hostName)),
    port: Port(service.port)
  ); 

  dynamic toJsonObject() => { "address": address.address.toString(), "port": port.value.toString() };
  String toJson() => jsonDecode(toJsonObject());
}

class HomeToucherLocation {
  final double latitude;
  final double longitude;

  HomeToucherLocation({@required this.latitude, @required this.longitude});

  factory HomeToucherLocation.fromService(MDNSService service) {
    final txtMap = service.map['txt'];

    return txtMap != null ? HomeToucherLocation(
      longitude: double.parse(utf8.decode(txtMap['longitude'])),
      latitude: double.parse(utf8.decode(txtMap['latitude'])),
    ) : null;
  }

  factory HomeToucherLocation.fromJsonObject(Map<String, dynamic> jsonObject) {
    if(jsonObject.containsKey("longitude") && jsonObject.containsKey("latitude"))
      return HomeToucherLocation(latitude: double.parse(jsonObject["latitude"]), longitude: double.parse(jsonObject["longitude"]));
    else
     return null;
  }

  factory HomeToucherLocation.fromJson(String json) => HomeToucherLocation.fromJsonObject(jsonDecode(json));

  dynamic toJsonObject() => { "latitude": latitude.toString(), "longitude": longitude.toString() };

  String toJson() => jsonDecode(toJsonObject());

  static double distanceBetween(HomeToucherLocation l1, HomeToucherLocation l2) {
    final p = 0.017453292519943295;
    final a = 0.5 - cos((l2.latitude - l1.latitude) * p)/2 +
      cos(l1.latitude * p) * cos(l2.latitude* p) *
      (1 - cos((l2.longitude - l1.longitude) * p))/2;

    return 12742 * asin(sqrt(a));
  } 

  double distanceFrom(HomeToucherLocation other) => distanceBetween(this, other); 
}
