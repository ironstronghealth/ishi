import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

const _kDisclaimerAcceptedKey = 'disclaimerAcceptedAt'; // stores ISO timestamp

class DisclaimerGate {
  /// Call this before navigating to the AI Check screen.
  /// Set [alwaysShow] = true if you want the popup every time (ignores saved consent).
  static Future<bool> ensureAccepted(BuildContext context, {bool alwaysShow = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final alreadyAccepted = prefs.containsKey(_kDisclaimerAcceptedKey);

    if (alreadyAccepted && !alwaysShow) return true;

    final accepted = await showDialog<bool>(
      context: context,
      useRootNavigator: true,         // <— IMPORTANT
      barrierDismissible: false,
      builder: (ctx) => const _DisclaimerDialog(),
    );

    if (accepted == true) {
      await prefs.setString(_kDisclaimerAcceptedKey, DateTime.now().toUtc().toIso8601String());
      return true;
    }
    return false;
  }
}

class _DisclaimerDialog extends StatefulWidget {
  const _DisclaimerDialog({Key? key}) : super(key: key);

  @override
  State<_DisclaimerDialog> createState() => _DisclaimerDialogState();
}

class _DisclaimerDialogState extends State<_DisclaimerDialog> {
  bool _agreed = false;

  Future<void> _openPolicy() async {
    final uri = Uri.parse('https://www.ironstronginitiative.com/privacy');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open Privacy Policy')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Important: Not a Medical Device'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ISHI provides an AI-assisted anemia risk indication from an eyelid photo. '
              'It is for awareness only and is NOT a diagnosis or a substitute for professional medical advice.',
            ),
            const SizedBox(height: 12),
            const Text('By continuing, you acknowledge that:'),
            const SizedBox(height: 6),
            const _Bullet('Results may be inaccurate and can be affected by lighting, camera quality, and positioning.'),
            const _Bullet('You will not rely on this app to make medical decisions.'),
            const _Bullet('If you have symptoms or concerns, you will consult a qualified clinician.'),
            const SizedBox(height: 12),
            InkWell(
              onTap: _openPolicy,
              child: const Text(
                'Privacy Policy',
                style: TextStyle(decoration: TextDecoration.underline, color: Colors.blueAccent),
              ),
            ),
            const SizedBox(height: 12),
            // Use CheckboxListTile to ensure the whole row is tappable
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _agreed,
              onChanged: (v) => setState(() => _agreed = v ?? false),
              title: const Text('I have read and agree'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _agreed
              ? () => Navigator.of(context, rootNavigator: true).pop(true)
              : null,
          child: const Text('Continue'),
        ),
      ],
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet(this.text, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('•  '),
        Expanded(child: Text(text)),
      ]);
}
