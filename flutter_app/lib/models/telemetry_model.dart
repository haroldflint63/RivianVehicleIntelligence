// ── lib/models/telemetry_model.dart ─────────────────────────────────

class TelemetryData {
  final double motorTemp;
  final double batteryPercent;
  final double outsideTemp;
  final double vehicleSpeed;
  final double batteryVoltage;
  final double cabinTemp;    // °F — HVAC interior temperature
  final double regenPower;   // kW — regenerative braking capture
  final double motorRpm;     // Motor revolutions per minute
  final double timestamp;

  const TelemetryData({
    required this.motorTemp,
    required this.batteryPercent,
    required this.outsideTemp,
    required this.vehicleSpeed,
    required this.batteryVoltage,
    this.cabinTemp = 72.0,
    this.regenPower = 0.0,
    this.motorRpm = 0.0,
    required this.timestamp,
  });

  factory TelemetryData.fromJson(Map<String, dynamic> json) => TelemetryData(
        motorTemp:      (json['motor_temp']       as num?)?.toDouble() ?? 0.0,
        batteryPercent: (json['battery_percent']  as num?)?.toDouble() ?? 100.0,
        outsideTemp:    (json['outside_temp']     as num?)?.toDouble() ?? 72.0,
        vehicleSpeed:   (json['vehicle_speed']    as num?)?.toDouble() ?? 0.0,
        batteryVoltage: (json['battery_voltage']  as num?)?.toDouble() ?? 355.0,
        cabinTemp: (json['cabin_temp'] as num?)?.toDouble() ?? 72.0,
        regenPower: (json['regen_power'] as num?)?.toDouble() ?? 0.0,
        motorRpm: (json['motor_rpm'] as num?)?.toDouble() ?? 0.0,
        timestamp: (json['timestamp'] as num?)?.toDouble() ??
            DateTime.now().millisecondsSinceEpoch / 1000.0,
      );
}
