import 'package:chess_trainer/domain/session/grade.dart';
import 'package:flutter/material.dart';

/// The self-grade (FR-026), which is the authoritative assessment (FR-027).
///
/// The four buttons are styled identically and none is preselected. Suggesting
/// one from the match indicator would make the measurement into the verdict,
/// which is the thing this feature exists not to do.
///
/// That used to be underwritten by incapacity: without an engine there was
/// nothing here that could make such a suggestion honestly. **Feature 005
/// removed that excuse.** An engine now judges positions their author left
/// unsolved, and it would be entirely possible to preselect "Missed it" for a
/// line the engine scores badly.
///
/// It must not. The player's own judgement of how the calculation went is the
/// record that counts, and an app that grades for them is measuring something
/// else — how close they came to a machine, rather than how well they thought.
class GradeButtons extends StatelessWidget {
  const GradeButtons({super.key, required this.selected, required this.onGrade});

  final GradeValue? selected;
  final ValueChanged<GradeValue> onGrade;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('How did that go?',
            style: Theme.of(context).textTheme.labelLarge,
            textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final value in GradeValue.values)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: _GradeButton(
                    key: Key('grade-${value.name}'),
                    value: value,
                    isSelected: selected == value,
                    onPressed: () => onGrade(value),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _GradeButton extends StatelessWidget {
  const _GradeButton({
    super.key,
    required this.value,
    required this.isSelected,
    required this.onPressed,
  });

  final GradeValue value;
  final bool isSelected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    // Four buttons across a phone leaves little room, and a label broken
    // mid-word ("Miss / ed it") reads as a glitch. Shrink to fit instead.
    final label = FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        value.label,
        maxLines: 1,
        softWrap: false,
        textAlign: TextAlign.center,
      ),
    );
    const style = ButtonStyle(
      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 6)),
    );

    // The only difference between the four is which one the user picked.
    return isSelected
        ? FilledButton(onPressed: onPressed, style: style, child: label)
        : OutlinedButton(onPressed: onPressed, style: style, child: label);
  }
}
