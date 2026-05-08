import 'package:flutter/material.dart';
import '../../models/race.dart';
import '../../theme/app_theme.dart';
import 'bike_picker.dart';

/// Dialog showing basic info of a participant's bike.
///
/// When [onChange] is provided, a "Change Bike" action is shown, calling
/// [onChange] with the new bike id (or null to clear) after the user picks.
class BikeInfoDialog {
  BikeInfoDialog._();

  static Future<void> show(
    BuildContext context, {
    required RaceParticipant participant,
    ValueChanged<int?>? onChange,
  }) async {
    if (participant.bicycleId == null) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor:
                      AppColors.primary.withValues(alpha: 0.12),
                  backgroundImage: participant.bicycleImageUrl != null
                      ? NetworkImage(participant.bicycleImageUrl!)
                      : null,
                  child: participant.bicycleImageUrl == null
                      ? const Icon(Icons.two_wheeler,
                          color: AppColors.primary, size: 28)
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        participant.bicycleName ?? 'Bike',
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary),
                      ),
                      if (participant.userName != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            'Owner: ${participant.userName}',
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary),
                          ),
                        ),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 12),
              if (participant.bicycleBrand != null)
                _row(Icons.business, 'Brand', participant.bicycleBrand!),
              if (participant.bicycleModel != null)
                _row(Icons.directions_bike, 'Model',
                    participant.bicycleModel!),
              if (participant.bicycleMotor != null &&
                  participant.bicycleMotor!.isNotEmpty)
                _row(Icons.bolt, 'Motor', participant.bicycleMotor!),
              if (participant.bicycleBattery != null &&
                  participant.bicycleBattery!.isNotEmpty)
                _row(Icons.battery_charging_full, 'Battery',
                    participant.bicycleBattery!),
              if (participant.bicycleBrand == null &&
                  participant.bicycleModel == null &&
                  (participant.bicycleMotor == null ||
                      participant.bicycleMotor!.isEmpty) &&
                  (participant.bicycleBattery == null ||
                      participant.bicycleBattery!.isEmpty))
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('No additional details.',
                      style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary)),
                ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (onChange != null) ...[
                    TextButton.icon(
                      icon: const Icon(Icons.swap_horiz, size: 18),
                      label: const Text('Change Bike'),
                      style: TextButton.styleFrom(
                          foregroundColor: AppColors.primary),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await showBikePickerSheet(
                          context,
                          selectedBikeId: participant.bicycleId,
                          onSelected: onChange,
                        );
                      },
                    ),
                    const SizedBox(width: 4),
                  ],
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _row(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          SizedBox(
            width: 64,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}
