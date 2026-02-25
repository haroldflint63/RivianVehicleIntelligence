// ── lib/services/service_api.dart ────────────────────────────────────
//
// Free API integrations for the Service tab:
//
// 1. Open-Meteo — weather at vehicle / service center (no key needed)
// 2. Open Charge Map — real EV charging stations nearby (no key needed
//    for low-volume; free API key optional)
// 3. NHTSA — vehicle recall & complaint lookup (free, no key)
// 4. ipinfo.io — approximate vehicle geolocation (free tier, no key)

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

// ── Weather ─────────────────────────────────────────────────────────
class WeatherData {
  final double tempF;
  final double windMph;
  final int humidity;
  final int weatherCode;
  final String description;
  final bool isDay;

  const WeatherData({
    required this.tempF,
    required this.windMph,
    required this.humidity,
    required this.weatherCode,
    required this.description,
    required this.isDay,
  });
}

// WMO weather codes → human descriptions
String _wmoDescription(int code) {
  return switch (code) {
    0 => 'Clear sky',
    1 => 'Mainly clear',
    2 => 'Partly cloudy',
    3 => 'Overcast',
    45 || 48 => 'Fog',
    51 || 53 || 55 => 'Drizzle',
    56 || 57 => 'Freezing drizzle',
    61 || 63 || 65 => 'Rain',
    66 || 67 => 'Freezing rain',
    71 || 73 || 75 => 'Snow',
    77 => 'Snow grains',
    80 || 81 || 82 => 'Rain showers',
    85 || 86 => 'Snow showers',
    95 => 'Thunderstorm',
    96 || 99 => 'Thunderstorm with hail',
    _ => 'Unknown',
  };
}

Future<WeatherData?> fetchWeather(double lat, double lng) async {
  try {
    final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$lat&longitude=$lng'
        '&current=temperature_2m,relative_humidity_2m,wind_speed_10m,weather_code,is_day'
        '&temperature_unit=fahrenheit&wind_speed_unit=mph');
    final resp = await http.get(url).timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) return null;
    final j = jsonDecode(resp.body);
    final c = j['current'];
    final code = (c['weather_code'] as num).toInt();
    return WeatherData(
      tempF: (c['temperature_2m'] as num).toDouble(),
      windMph: (c['wind_speed_10m'] as num).toDouble(),
      humidity: (c['relative_humidity_2m'] as num).toInt(),
      weatherCode: code,
      description: _wmoDescription(code),
      isDay: (c['is_day'] as num).toInt() == 1,
    );
  } catch (e) {
    debugPrint('[ServiceAPI] Weather error: $e');
    return null;
  }
}

// ── Nearby EV Chargers (Open Charge Map) ─────────────────────────────
class EvCharger {
  final String name;
  final String address;
  final double lat;
  final double lng;
  final double distanceMiles;
  final int numPoints;        // # of charge points at this location
  final String? network;      // e.g. "ChargePoint", "Tesla Supercharger"
  final String? powerKw;      // max power level
  final bool isFastCharge;

  const EvCharger({
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
    required this.distanceMiles,
    required this.numPoints,
    this.network,
    this.powerKw,
    required this.isFastCharge,
  });
}

Future<List<EvCharger>> fetchNearbyChargers(double lat, double lng,
    {int maxResults = 12, double radiusMiles = 25}) async {
  try {
    final url = Uri.parse(
        'https://api.openchargemap.io/v3/poi'
        '?output=json&latitude=$lat&longitude=$lng'
        '&distance=$radiusMiles&distanceunit=Miles'
        '&maxresults=$maxResults&compact=true&verbose=false');
    final resp = await http.get(url, headers: {
      'User-Agent': 'RivianVehicleIntelligence/1.0',
    }).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return [];
    final List<dynamic> items = jsonDecode(resp.body);
    return items.map((j) {
      final addr = j['AddressInfo'] ?? {};
      final conns = (j['Connections'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final maxKw = conns
          .map((c) => (c['PowerKW'] as num?)?.toDouble() ?? 0)
          .fold<double>(0, (a, b) => a > b ? a : b);
      return EvCharger(
        name: addr['Title'] as String? ?? 'EV Charger',
        address: '${addr['AddressLine1'] ?? ''}, ${addr['Town'] ?? ''}, ${addr['StateOrProvince'] ?? ''}',
        lat: (addr['Latitude'] as num?)?.toDouble() ?? lat,
        lng: (addr['Longitude'] as num?)?.toDouble() ?? lng,
        distanceMiles: (addr['Distance'] as num?)?.toDouble() ?? 0,
        numPoints: (j['NumberOfPoints'] as num?)?.toInt() ?? conns.length,
        network: (j['OperatorInfo'] as Map?)? ['Title'] as String?,
        powerKw: maxKw > 0 ? '${maxKw.toStringAsFixed(0)} kW' : null,
        isFastCharge: maxKw >= 50,
      );
    }).toList()
      ..sort((a, b) => a.distanceMiles.compareTo(b.distanceMiles));
  } catch (e) {
    debugPrint('[ServiceAPI] Charger error: $e');
    return [];
  }
}

// ── NHTSA Recalls ────────────────────────────────────────────────────
class NhtsaRecall {
  final String component;
  final String summary;
  final String consequence;
  final String remedy;
  final String nhtsaId;
  final String reportDate;

  const NhtsaRecall({
    required this.component,
    required this.summary,
    required this.consequence,
    required this.remedy,
    required this.nhtsaId,
    required this.reportDate,
  });
}

Future<List<NhtsaRecall>> fetchRecalls(
    {String make = 'RIVIAN', int year = 2024, String model = 'R1T'}) async {
  try {
    final url = Uri.parse(
        'https://api.nhtsa.gov/recalls/recallsByVehicle'
        '?make=$make&model=$model&modelYear=$year');
    final resp = await http.get(url).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return [];
    final j = jsonDecode(resp.body);
    final List<dynamic> results = j['results'] ?? [];
    return results.map((r) => NhtsaRecall(
          component: r['Component'] as String? ?? '',
          summary: r['Summary'] as String? ?? '',
          consequence: r['Consequence'] as String? ?? '',
          remedy: r['Remedy'] as String? ?? '',
          nhtsaId: r['NHTSACampaignNumber'] as String? ?? '',
          reportDate: r['ReportReceivedDate'] as String? ?? '',
        )).toList();
  } catch (e) {
    debugPrint('[ServiceAPI] NHTSA error: $e');
    return [];
  }
}

// ── NHTSA Complaints ─────────────────────────────────────────────────
class NhtsaComplaint {
  final String component;
  final String summary;
  final int odiNumber;
  final String dateComplaint;
  final bool crash;
  final bool fire;

  const NhtsaComplaint({
    required this.component,
    required this.summary,
    required this.odiNumber,
    required this.dateComplaint,
    required this.crash,
    required this.fire,
  });
}

Future<List<NhtsaComplaint>> fetchComplaints(
    {String make = 'RIVIAN', int year = 2024, String model = 'R1T'}) async {
  try {
    final url = Uri.parse(
        'https://api.nhtsa.gov/complaints/complaintsByVehicle'
        '?make=$make&model=$model&modelYear=$year');
    final resp = await http.get(url).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return [];
    final j = jsonDecode(resp.body);
    final List<dynamic> results = j['results'] ?? [];
    return results.take(20).map((r) => NhtsaComplaint(
          component: r['components'] as String? ?? '',
          summary: r['summary'] as String? ?? '',
          odiNumber: (r['odiNumber'] as num?)?.toInt() ?? 0,
          dateComplaint: r['dateComplaintFiled'] as String? ?? '',
          crash: r['crash'] == true || r['crash'] == 'Yes',
          fire: r['fire'] == true || r['fire'] == 'Yes',
        )).toList();
  } catch (e) {
    debugPrint('[ServiceAPI] Complaints error: $e');
    return [];
  }
}

// ── Geolocation via ipinfo.io (fallback) ─────────────────────────────
class GeoLocation {
  final double lat;
  final double lng;
  final String city;
  final String region;

  const GeoLocation({
    required this.lat,
    required this.lng,
    required this.city,
    required this.region,
  });
}

Future<GeoLocation?> fetchApproxLocation() async {
  try {
    final resp = await http
        .get(Uri.parse('https://ipinfo.io/json'))
        .timeout(const Duration(seconds: 6));
    if (resp.statusCode != 200) return null;
    final j = jsonDecode(resp.body);
    final loc = (j['loc'] as String?)?.split(',');
    if (loc == null || loc.length != 2) return null;
    return GeoLocation(
      lat: double.parse(loc[0]),
      lng: double.parse(loc[1]),
      city: j['city'] as String? ?? '',
      region: j['region'] as String? ?? '',
    );
  } catch (e) {
    debugPrint('[ServiceAPI] Geo error: $e');
    return null;
  }
}
