// ── lib/screens/service_screen.dart ─────────────────────────────────
//
// Rivian Service & Intelligence Hub — powered by free live APIs:
//   • Open-Meteo weather at vehicle location
//   • Open Charge Map nearby EV chargers
//   • NHTSA vehicle recall & complaint data
//   • ipinfo.io approximate geolocation
//   • Rivian service center directory with distance sorting

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../services/websocket_service.dart';
import '../services/service_api.dart';
import 'live_chat_screen.dart';

// ── Rivian service center data ────────────────────────────────────────
class _ServiceCenter {
  final String name, address, city, state, zip, phone, hours;
  final double lat, lng;
  final bool mobileService, charging;

  const _ServiceCenter({
    required this.name, required this.address, required this.city,
    required this.state, required this.zip, required this.phone,
    required this.hours, required this.lat, required this.lng,
    this.mobileService = false, this.charging = true,
  });

  String get fullAddress => '$address, $city, $state $zip';
}

const _centers = <_ServiceCenter>[
  _ServiceCenter(name: 'Rivian Irvine Service Center', address: '14600 Myford Rd', city: 'Irvine', state: 'CA', zip: '92606', phone: '+1 (888) 748-4261', hours: 'Mon–Fri 8 AM–6 PM PT', lat: 33.6846, lng: -117.8265, mobileService: true, charging: true),
  _ServiceCenter(name: 'Rivian Laguna Hills Service Center', address: '23052 Alicia Pkwy', city: 'Laguna Hills', state: 'CA', zip: '92653', phone: '+1 (888) 748-4261', hours: 'Mon–Fri 8 AM–6 PM PT', lat: 33.6003, lng: -117.7078, mobileService: true),
  _ServiceCenter(name: 'Rivian Norwalk Service Center', address: '12438 Firestone Blvd', city: 'Norwalk', state: 'CA', zip: '90650', phone: '+1 (888) 748-4261', hours: 'Mon–Fri 8 AM–6 PM PT', lat: 33.9040, lng: -118.0820),
  _ServiceCenter(name: 'Rivian Chicago Service Center', address: '2245 S Michigan Ave', city: 'Chicago', state: 'IL', zip: '60616', phone: '+1 (888) 748-4261', hours: 'Mon–Fri 8 AM–6 PM CT', lat: 41.8498, lng: -87.6238, mobileService: true),
  _ServiceCenter(name: 'Rivian New York Service Center', address: '412 W 15th St', city: 'New York', state: 'NY', zip: '10011', phone: '+1 (888) 748-4261', hours: 'Mon–Fri 8 AM–6 PM ET', lat: 40.7425, lng: -74.0072, mobileService: true),
  _ServiceCenter(name: 'Rivian Austin Service Center', address: '600 E 5th St', city: 'Austin', state: 'TX', zip: '78701', phone: '+1 (888) 748-4261', hours: 'Mon–Fri 8 AM–6 PM CT', lat: 30.2672, lng: -97.7431, mobileService: true),
  _ServiceCenter(name: 'Rivian Denver Service Center', address: '2501 E Colfax Ave', city: 'Denver', state: 'CO', zip: '80206', phone: '+1 (888) 748-4261', hours: 'Mon–Fri 8 AM–6 PM MT', lat: 39.7407, lng: -104.9479),
  _ServiceCenter(name: 'Rivian Atlanta Service Center', address: '850 Ponce De Leon Ave NE', city: 'Atlanta', state: 'GA', zip: '30306', phone: '+1 (888) 748-4261', hours: 'Mon–Fri 8 AM–6 PM ET', lat: 33.7724, lng: -84.3617, mobileService: true),
  _ServiceCenter(name: 'Rivian Seattle Service Center', address: '2600 1st Ave', city: 'Seattle', state: 'WA', zip: '98121', phone: '+1 (888) 748-4261', hours: 'Mon–Fri 8 AM–6 PM PT', lat: 47.6154, lng: -122.3531, mobileService: true),
  _ServiceCenter(name: 'Rivian Miami Service Center', address: '1801 NW 22nd Ct', city: 'Miami', state: 'FL', zip: '33142', phone: '+1 (888) 748-4261', hours: 'Mon–Fri 8 AM–6 PM ET', lat: 25.7959, lng: -80.2262),
  _ServiceCenter(name: 'Rivian Normal HQ & Service', address: '100 Normal Ave', city: 'Normal', state: 'IL', zip: '61761', phone: '+1 (888) 748-4261', hours: 'Mon–Fri 8 AM–5 PM CT', lat: 40.5142, lng: -88.9906),
];

double _miles(double lat1, double lng1, double lat2, double lng2) {
  const r = 3958.8;
  final dLat = (lat2 - lat1) * pi / 180;
  final dLng = (lng2 - lng1) * pi / 180;
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1 * pi / 180) * cos(lat2 * pi / 180) * sin(dLng / 2) * sin(dLng / 2);
  return r * 2 * atan2(sqrt(a), sqrt(1 - a));
}

// ── Screen ────────────────────────────────────────────────────────────
class ServiceScreen extends StatefulWidget {
  const ServiceScreen({super.key});
  @override
  State<ServiceScreen> createState() => _ServiceScreenState();
}

class _ServiceScreenState extends State<ServiceScreen> {
  // Location
  double _lat = 41.8781;
  double _lng = -87.6298;
  String _locationLabel = 'Chicago, IL';
  bool _locating = true;

  // API data
  WeatherData? _weather;
  List<EvCharger> _chargers = [];
  List<NhtsaRecall> _recalls = [];
  List<NhtsaComplaint> _complaints = [];
  bool _loadingWeather = true;
  bool _loadingChargers = true;
  bool _loadingRecalls = true;
  bool _loadingComplaints = true;

  // Service centers sorted by distance
  late List<({_ServiceCenter center, double miles})> _sorted;

  @override
  void initState() {
    super.initState();
    _sorted = _sortCenters();
    _initApis();
  }

  List<({_ServiceCenter center, double miles})> _sortCenters() {
    return _centers
        .map((c) => (center: c, miles: _miles(_lat, _lng, c.lat, c.lng)))
        .toList()
      ..sort((a, b) => a.miles.compareTo(b.miles));
  }

  Future<void> _initApis() async {
    // 1. Get approx location
    final geo = await fetchApproxLocation();
    if (geo != null && mounted) {
      setState(() {
        _lat = geo.lat;
        _lng = geo.lng;
        _locationLabel = '${geo.city}, ${geo.region}';
        _locating = false;
        _sorted = _sortCenters();
      });
    } else if (mounted) {
      setState(() => _locating = false);
    }

    // 2. Fetch all APIs in parallel
    final results = await Future.wait([
      fetchWeather(_lat, _lng),
      fetchNearbyChargers(_lat, _lng),
      fetchRecalls(),
      fetchComplaints(),
    ]);

    if (!mounted) return;
    setState(() {
      _weather = results[0] as WeatherData?;
      _chargers = results[1] as List<EvCharger>;
      _recalls = results[2] as List<NhtsaRecall>;
      _complaints = results[3] as List<NhtsaComplaint>;
      _loadingWeather = false;
      _loadingChargers = false;
      _loadingRecalls = false;
      _loadingComplaints = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<WebSocketService>(builder: (_, svc, __) {
      final healthScore = svc.healthScore;
      final healthStatus = svc.healthStatus;

      return CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          const SliverToBoxAdapter(child: SizedBox(height: 16)),

          // ── Vehicle status banner ─────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverToBoxAdapter(
              child: _VehicleStatusBanner(
                healthScore: healthScore,
                healthStatus: healthStatus,
                connected: svc.connectionState == WsState.connected,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),

          // ── Live weather card ─────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverToBoxAdapter(
              child: _WeatherCard(
                weather: _weather,
                loading: _loadingWeather,
                location: _locationLabel,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),

          // ── Contact bar ───────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverToBoxAdapter(child: _ContactBar()),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),

          // ── Nearby EV chargers ────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverToBoxAdapter(
              child: _SectionHeader(
                icon: Icons.ev_station_rounded,
                label: 'NEARBY EV CHARGING',
                trailing: _loadingChargers
                    ? 'Loading…'
                    : '${_chargers.length} stations found',
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 10)),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverToBoxAdapter(
              child: _loadingChargers
                  ? _LoadingShimmer()
                  : _chargers.isEmpty
                      ? _EmptyState(message: 'No chargers found nearby')
                      : _ChargerList(chargers: _chargers),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),

          // ── NHTSA Recalls ─────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverToBoxAdapter(
              child: _SectionHeader(
                icon: Icons.shield_rounded,
                label: 'NHTSA SAFETY RECALLS',
                trailing: _loadingRecalls
                    ? 'Loading…'
                    : '${_recalls.length} recalls · R1T 2024',
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 10)),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverToBoxAdapter(
              child: _loadingRecalls
                  ? _LoadingShimmer()
                  : _recalls.isEmpty
                      ? _StatusPill(
                          icon: Icons.check_circle_rounded,
                          label: 'No open recalls for 2024 R1T',
                          color: RivianColors.green)
                      : _RecallList(recalls: _recalls),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),

          // ── NHTSA Complaints ──────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverToBoxAdapter(
              child: _SectionHeader(
                icon: Icons.report_problem_rounded,
                label: 'NHTSA OWNER COMPLAINTS',
                trailing: _loadingComplaints
                    ? 'Loading…'
                    : '${_complaints.length} reports · R1T 2024',
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 10)),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverToBoxAdapter(
              child: _loadingComplaints
                  ? _LoadingShimmer()
                  : _complaints.isEmpty
                      ? _StatusPill(
                          icon: Icons.check_circle_rounded,
                          label: 'No complaints on file for 2024 R1T',
                          color: RivianColors.green)
                      : _ComplaintList(complaints: _complaints),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),

          // ── Service centers ───────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverToBoxAdapter(
              child: _SectionHeader(
                icon: Icons.location_on_rounded,
                label: 'RIVIAN SERVICE CENTERS',
                trailing: _locating ? 'Locating…' : 'Near $_locationLabel',
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 10)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 48),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => _ServiceCenterTile(
                  center: _sorted[i].center,
                  distanceMiles: _sorted[i].miles,
                  isNearest: i == 0,
                ),
                childCount: _sorted.length,
              ),
            ),
          ),
        ],
      );
    });
  }
}

// ══════════════════════════════════════════════════════════════════════
//  WIDGETS
// ══════════════════════════════════════════════════════════════════════

// ── Vehicle status banner ─────────────────────────────────────────────
class _VehicleStatusBanner extends StatelessWidget {
  const _VehicleStatusBanner({
    required this.healthScore,
    required this.healthStatus,
    required this.connected,
  });
  final double healthScore;
  final String healthStatus;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final needsService = healthScore < 70;
    final color = needsService ? RivianColors.warning : RivianColors.green;
    final icon = needsService ? Icons.build_circle_rounded : Icons.check_circle_rounded;
    final msg = needsService
        ? 'Health score ${healthScore.toStringAsFixed(0)}/100 — Service recommended'
        : 'Vehicle health $healthStatus — ${healthScore.toStringAsFixed(0)}/100';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(needsService ? 'Service Recommended' : 'Vehicle Healthy',
              style: RivianText.headingMd.copyWith(color: color)),
          const SizedBox(height: 3),
          Text(msg, style: RivianText.bodySm),
        ])),
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(
            color: connected ? RivianColors.green : RivianColors.textTertiary,
            shape: BoxShape.circle,
          ),
        ),
      ]),
    );
  }
}

// ── Live weather card ─────────────────────────────────────────────────
class _WeatherCard extends StatelessWidget {
  const _WeatherCard({
    required this.weather,
    required this.loading,
    required this.location,
  });
  final WeatherData? weather;
  final bool loading;
  final String location;

  IconData _weatherIcon(int code, bool isDay) {
    if (code == 0 || code == 1) return isDay ? Icons.wb_sunny_rounded : Icons.nightlight_rounded;
    if (code == 2) return Icons.cloud_queue_rounded;
    if (code == 3) return Icons.cloud_rounded;
    if (code >= 45 && code <= 48) return Icons.blur_on;
    if (code >= 51 && code <= 67) return Icons.grain_rounded;
    if (code >= 71 && code <= 86) return Icons.ac_unit_rounded;
    if (code >= 80 && code <= 82) return Icons.water_drop_rounded;
    if (code >= 95) return Icons.bolt_rounded;
    return Icons.cloud_rounded;
  }

  Color _weatherColor(int code) {
    if (code == 0 || code == 1) return RivianColors.warning;
    if (code >= 71 && code <= 86) return RivianColors.ice;
    if (code >= 95) return RivianColors.danger;
    return RivianColors.info;
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return _LoadingShimmer(height: 90);

    final w = weather;
    if (w == null) {
      return _StatusPill(
        icon: Icons.cloud_off_rounded,
        label: 'Weather unavailable',
        color: RivianColors.textTertiary,
      );
    }

    final ic = _weatherIcon(w.weatherCode, w.isDay);
    final col = _weatherColor(w.weatherCode);

    // Range impact estimate
    String rangeImpact = '';
    if (w.tempF < 32) {
      rangeImpact = '↓ ~20% range loss — cold battery';
    } else if (w.tempF < 45) {
      rangeImpact = '↓ ~10% range loss — cool conditions';
    } else if (w.tempF > 95) {
      rangeImpact = '↓ ~8% range loss — AC load';
    } else if (w.windMph > 25) {
      rangeImpact = '↓ ~5% range loss — headwind drag';
    } else {
      rangeImpact = '✓ Optimal conditions for range';
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [col.withValues(alpha: 0.08), RivianColors.bg1],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: col.withValues(alpha: 0.2), width: 1),
        boxShadow: RivianShadows.card,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          // Weather icon
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: col.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(ic, color: col, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('${w.tempF.toStringAsFixed(0)}°F',
                  style: RivianText.displayMd.copyWith(fontSize: 26)),
              const SizedBox(width: 10),
              Text(w.description,
                  style: RivianText.headingMd.copyWith(
                      color: col, fontSize: 12)),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              _MiniMetric(icon: Icons.air_rounded, value: '${w.windMph.toStringAsFixed(0)} mph'),
              const SizedBox(width: 14),
              _MiniMetric(icon: Icons.water_drop_outlined, value: '${w.humidity}%'),
              const SizedBox(width: 14),
              _MiniMetric(icon: Icons.location_on_outlined, value: location),
            ]),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: RivianColors.bg2,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                Icon(Icons.battery_charging_full_rounded,
                    size: 12, color: col),
                const SizedBox(width: 6),
                Expanded(child: Text(rangeImpact,
                    style: RivianText.caption.copyWith(
                        color: RivianColors.textSecondary, fontSize: 9))),
              ]),
            ),
          ])),
        ]),
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({required this.icon, required this.value});
  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 11, color: RivianColors.textTertiary),
        const SizedBox(width: 4),
        Text(value,
            style: RivianText.caption.copyWith(
                color: RivianColors.textSecondary, fontSize: 9)),
      ]);
}

// ── EV charger list ───────────────────────────────────────────────────
class _ChargerList extends StatelessWidget {
  const _ChargerList({required this.chargers});
  final List<EvCharger> chargers;

  @override
  Widget build(BuildContext context) {
    return Column(children: chargers.take(8).map((c) {
      final col = c.isFastCharge ? RivianColors.green : RivianColors.info;
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: RivianColors.bg1,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: RivianColors.border, width: 1),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: col.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              c.isFastCharge ? Icons.bolt_rounded : Icons.ev_station_rounded,
              color: col, size: 16,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.name, style: RivianText.headingMd.copyWith(fontSize: 12),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(c.address, style: RivianText.bodySm.copyWith(fontSize: 10),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Wrap(spacing: 6, children: [
              if (c.network != null)
                _PillTag(label: c.network!, color: RivianColors.info),
              if (c.powerKw != null)
                _PillTag(label: c.powerKw!, color: col),
              if (c.isFastCharge)
                _PillTag(label: 'DC Fast', color: RivianColors.green),
              _PillTag(label: '${c.numPoints} ports', color: RivianColors.textSecondary),
            ]),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(c.distanceMiles < 1
                    ? '${(c.distanceMiles * 5280).toStringAsFixed(0)} ft'
                    : '${c.distanceMiles.toStringAsFixed(1)} mi',
                style: RivianText.headingMd.copyWith(
                    color: col, fontSize: 13)),
            Text('away', style: RivianText.caption),
          ]),
        ]),
      );
    }).toList());
  }
}

// ── Recall list ───────────────────────────────────────────────────────
class _RecallList extends StatelessWidget {
  const _RecallList({required this.recalls});
  final List<NhtsaRecall> recalls;

  @override
  Widget build(BuildContext context) {
    return Column(children: recalls.map((r) {
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: RivianColors.bg1,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: RivianColors.warning.withValues(alpha: 0.25), width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Accent bar
          Container(height: 2, color: RivianColors.warning.withValues(alpha: 0.7)),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.shield_rounded, size: 14, color: RivianColors.warning),
                const SizedBox(width: 8),
                Expanded(child: Text(r.component,
                    style: RivianText.headingMd.copyWith(fontSize: 12))),
                _PillTag(label: r.nhtsaId, color: RivianColors.warning),
              ]),
              const SizedBox(height: 8),
              Text(r.summary, style: RivianText.bodySm.copyWith(fontSize: 11, height: 1.5),
                  maxLines: 3, overflow: TextOverflow.ellipsis),
              if (r.remedy.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: RivianColors.green.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.build_rounded, size: 12, color: RivianColors.green),
                    const SizedBox(width: 8),
                    Expanded(child: Text(r.remedy,
                        style: RivianText.caption.copyWith(
                            color: RivianColors.textSecondary, fontSize: 10, height: 1.4),
                        maxLines: 2, overflow: TextOverflow.ellipsis)),
                  ]),
                ),
              ],
            ]),
          ),
        ]),
      );
    }).toList());
  }
}

// ── Complaint list ────────────────────────────────────────────────────
class _ComplaintList extends StatelessWidget {
  const _ComplaintList({required this.complaints});
  final List<NhtsaComplaint> complaints;

  @override
  Widget build(BuildContext context) {
    return Column(children: complaints.take(10).map((c) {
      final hasIncident = c.crash || c.fire;
      final col = hasIncident ? RivianColors.danger : RivianColors.textSecondary;

      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: RivianColors.bg1,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: RivianColors.border, width: 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.report_problem_rounded, size: 13, color: col),
            const SizedBox(width: 8),
            Expanded(child: Text(c.component,
                style: RivianText.headingMd.copyWith(fontSize: 11),
                maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (c.crash) _PillTag(label: 'CRASH', color: RivianColors.danger),
            if (c.fire) ...[
              const SizedBox(width: 4),
              _PillTag(label: 'FIRE', color: RivianColors.danger),
            ],
            if (c.dateComplaint.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text(c.dateComplaint.length >= 10 ? c.dateComplaint.substring(0, 10) : c.dateComplaint,
                  style: RivianText.caption.copyWith(fontSize: 8)),
            ],
          ]),
          const SizedBox(height: 6),
          Text(c.summary, style: RivianText.bodySm.copyWith(fontSize: 10, height: 1.5),
              maxLines: 3, overflow: TextOverflow.ellipsis),
        ]),
      );
    }).toList());
  }
}

// ── Contact bar ───────────────────────────────────────────────────────
class _ContactBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SectionHeader(icon: Icons.support_agent_rounded, label: 'CONTACT RIVIAN'),
      const SizedBox(height: 12),

      // ── Live Chat — big primary CTA ────────────────────────────
      GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const LiveChatScreen()),
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                RivianColors.green.withValues(alpha: 0.15),
                RivianColors.green.withValues(alpha: 0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: RivianColors.green.withValues(alpha: 0.35), width: 1),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: RivianColors.green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.support_agent_rounded,
                  size: 22, color: RivianColors.green),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Rivian Support AI',
                  style: RivianText.headingMd.copyWith(
                      color: RivianColors.green, fontSize: 14)),
              const SizedBox(height: 3),
              Text('Live chat with vehicle-aware AI assistant',
                  style: RivianText.bodySm.copyWith(
                      color: RivianColors.textSecondary, fontSize: 11)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: RivianColors.green.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 6, height: 6,
                  decoration: const BoxDecoration(
                    color: RivianColors.green, shape: BoxShape.circle),
                ),
                const SizedBox(width: 5),
                Text('LIVE', style: RivianText.caption.copyWith(
                    color: RivianColors.green, fontWeight: FontWeight.w800, fontSize: 9)),
              ]),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 10),

      // ── Contact buttons row ────────────────────────────────────
      Row(children: [
        Expanded(child: _ContactBtn(
          icon: Icons.phone_rounded,
          label: 'Roadside',
          sub: '1-888-RIVIAN-1',
          color: RivianColors.danger,
          onTap: () => _copy(context, '1-888-748-4261'),
        )),
        const SizedBox(width: 10),
        Expanded(child: _ContactBtn(
          icon: Icons.language_rounded,
          label: 'Support',
          sub: 'rivian.com/support',
          color: RivianColors.info,
          onTap: () => _copy(context, 'https://rivian.com/support'),
        )),
        const SizedBox(width: 10),
        Expanded(child: _ContactBtn(
          icon: Icons.phone_android_rounded,
          label: 'Rivian App',
          sub: 'In-app messaging',
          color: RivianColors.green,
          onTap: () => _copy(context, 'https://rivian.com/app'),
        )),
      ]),
      const SizedBox(height: 10),

      // ── 24/7 banner ────────────────────────────────────────────
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: RivianColors.bg1,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: RivianColors.border, width: 1),
        ),
        child: Row(children: [
          const Icon(Icons.local_taxi_rounded, size: 16, color: RivianColors.warning),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('24/7 Roadside Assistance · 1-888-748-4261',
                style: RivianText.headingMd.copyWith(color: RivianColors.warning, fontSize: 12)),
            Text('Complimentary roadside assistance including flatbed towing, '
                'tire changes, lockouts, and jump starts. Available 24/7/365.',
                style: RivianText.bodySm.copyWith(fontSize: 11, height: 1.4)),
          ])),
        ]),
      ),
    ]);
  }

  static void _copy(BuildContext ctx, String v) {
    Clipboard.setData(ClipboardData(text: v));
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: Text('Copied: $v',
          style: RivianText.bodySm.copyWith(color: RivianColors.textPrimary)),
      backgroundColor: RivianColors.bg2,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }
}

class _ContactBtn extends StatefulWidget {
  const _ContactBtn({
    required this.icon, required this.label, required this.sub,
    required this.color, required this.onTap,
  });
  final IconData icon;
  final String label, sub;
  final Color color;
  final VoidCallback onTap;
  @override
  State<_ContactBtn> createState() => _ContactBtnState();
}

class _ContactBtnState extends State<_ContactBtn> {
  bool _pressed = false;

  void _tap() {
    widget.onTap();
    setState(() => _pressed = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _pressed = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = _pressed ? RivianColors.green : widget.color;
    return GestureDetector(
      onTap: _tap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.withValues(alpha: 0.25), width: 1),
        ),
        child: Column(children: [
          Icon(_pressed ? Icons.copy_rounded : widget.icon, color: c, size: 20),
          const SizedBox(height: 6),
          Text(_pressed ? 'Copied!' : widget.label,
              style: RivianText.headingMd.copyWith(color: c, fontSize: 11)),
          const SizedBox(height: 2),
          Text(widget.sub,
              style: RivianText.caption.copyWith(fontSize: 8),
              textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }
}

// ── Service center tile ───────────────────────────────────────────────
class _ServiceCenterTile extends StatefulWidget {
  const _ServiceCenterTile({
    required this.center, required this.distanceMiles, required this.isNearest,
  });
  final _ServiceCenter center;
  final double distanceMiles;
  final bool isNearest;
  @override
  State<_ServiceCenterTile> createState() => _ServiceCenterTileState();
}

class _ServiceCenterTileState extends State<_ServiceCenterTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.isNearest ? RivianColors.green : RivianColors.border;

    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: RivianColors.bg1,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.withValues(alpha: 0.4), width: 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: widget.isNearest
                      ? RivianColors.green.withValues(alpha: 0.12) : RivianColors.bg2,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(children: [
                  Text(widget.distanceMiles < 10
                          ? widget.distanceMiles.toStringAsFixed(1)
                          : widget.distanceMiles.toStringAsFixed(0),
                      style: RivianText.headingMd.copyWith(
                          color: widget.isNearest ? RivianColors.green : RivianColors.textPrimary,
                          fontSize: 16, fontWeight: FontWeight.w800)),
                  Text('mi', style: RivianText.caption.copyWith(
                      color: widget.isNearest ? RivianColors.green : RivianColors.textTertiary)),
                ]),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(widget.center.name,
                      style: RivianText.headingMd.copyWith(fontSize: 13))),
                  if (widget.isNearest)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: RivianColors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('NEAREST',
                          style: RivianText.caption.copyWith(
                              color: RivianColors.green, fontWeight: FontWeight.w800, fontSize: 8)),
                    ),
                ]),
                const SizedBox(height: 3),
                Text(widget.center.fullAddress, style: RivianText.bodySm.copyWith(fontSize: 11)),
                const SizedBox(height: 4),
                Row(children: [
                  if (widget.center.mobileService) ...[
                    _PillTag(label: 'Mobile Service', color: RivianColors.info),
                    const SizedBox(width: 5),
                  ],
                  if (widget.center.charging)
                    _PillTag(label: '⚡ Chargers', color: RivianColors.green),
                ]),
              ])),
              Icon(_expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                  color: RivianColors.textTertiary, size: 20),
            ]),
          ),
          if (_expanded) ...[
            Divider(height: 1, color: RivianColors.border),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _DetailRow(icon: Icons.access_time_rounded, label: 'Hours', value: widget.center.hours),
                const SizedBox(height: 10),
                _DetailRow(icon: Icons.navigation_rounded, label: 'Address', value: widget.center.fullAddress),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: _ActionBtn(
                    icon: Icons.phone_rounded, label: 'Call Service',
                    color: RivianColors.green,
                    onTap: () => _copy(context, widget.center.phone),
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: _ActionBtn(
                    icon: Icons.directions_rounded, label: 'Get Directions',
                    color: RivianColors.info,
                    onTap: () => _copy(context, '${widget.center.lat},${widget.center.lng}'),
                  )),
                ]),
              ]),
            ),
          ],
        ]),
      ),
    );
  }

  static void _copy(BuildContext ctx, String v) {
    Clipboard.setData(ClipboardData(text: v));
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: Text('Copied to clipboard',
          style: RivianText.bodySm.copyWith(color: RivianColors.textPrimary)),
      backgroundColor: RivianColors.bg2,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }
}

// ── Shared UI components ──────────────────────────────────────────────

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label, value;

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 13, color: RivianColors.textTertiary),
        const SizedBox(width: 8),
        Text('$label  ', style: RivianText.caption.copyWith(
            color: RivianColors.textTertiary, letterSpacing: 0.5)),
        Expanded(child: Text(value, style: RivianText.bodySm.copyWith(
            color: RivianColors.textPrimary, fontSize: 11))),
      ]);
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({required this.icon, required this.label, required this.color, required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.2), width: 1),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(label, style: RivianText.headingMd.copyWith(color: color, fontSize: 11)),
          ]),
        ),
      );
}

class _PillTag extends StatelessWidget {
  const _PillTag({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label, style: RivianText.caption.copyWith(
            color: color, fontSize: 8, fontWeight: FontWeight.w700)),
      );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.label, this.trailing});
  final IconData icon;
  final String label;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 13, color: RivianColors.textTertiary),
        const SizedBox(width: 6),
        Text(label, style: RivianText.label.copyWith(
            color: RivianColors.textTertiary, letterSpacing: 1.4, fontSize: 10)),
        const Spacer(),
        if (trailing != null)
          Row(children: [
            const Icon(Icons.my_location_rounded, size: 10, color: RivianColors.info),
            const SizedBox(width: 4),
            Text(trailing!, style: RivianText.caption.copyWith(
                color: RivianColors.info, fontSize: 9)),
          ]),
      ]);
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2), width: 1),
        ),
        child: Row(children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Text(label, style: RivianText.headingMd.copyWith(color: color, fontSize: 12)),
        ]),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: RivianColors.bg1,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: RivianColors.border, width: 1),
        ),
        child: Center(child: Text(message, style: RivianText.bodySm)),
      );
}

class _LoadingShimmer extends StatelessWidget {
  const _LoadingShimmer({this.height = 60});
  final double height;

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        decoration: BoxDecoration(
          color: RivianColors.bg1,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: RivianColors.border, width: 1),
        ),
        child: const Center(
          child: SizedBox(
            width: 18, height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: RivianColors.green,
            ),
          ),
        ),
      );
}
