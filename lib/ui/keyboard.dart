import 'package:flutter/widgets.dart';

/// Hides the on-screen keyboard by unfocusing the current text field.
void dismissKeyboard(BuildContext context) => FocusScope.of(context).unfocus();

/// Dismisses the keyboard when the user taps anywhere that isn't itself
/// interactive. Interactive widgets win the tap, so this never steals a
/// button press or a tap into another field.
class DismissKeyboardOnTap extends StatelessWidget {
  const DismissKeyboardOnTap({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    // Above the Navigator there is no route scope, so use the primary focus.
    onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
    child: child,
  );
}
