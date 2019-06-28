import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:keyboard_actions/keyboard_actions.dart';
import 'package:osu/utils/textField-formatter.dart';

List<KeyboardAction> actions = [];

class DecimalInput extends StatefulWidget {
  final String labelText;

  DecimalInput({Key key, this.labelText}) : super(key: key);

  @override
  _DecimalInputState createState() => _DecimalInputState();
}

class _DecimalInputState extends State<DecimalInput> {
  FocusNode focusNode = FocusNode();

  KeyboardActionsConfig _buildConfig(BuildContext context) {
    return KeyboardActionsConfig(
      keyboardActionsPlatform: KeyboardActionsPlatform.ALL,
      keyboardBarColor: Colors.grey[200],
      nextFocus: false,
      actions: actions,
    );
  }

  @override
  void initState() {
    // save focusNode to actions
    actions.add(KeyboardAction(
      focusNode: focusNode,
    ));

    FormKeyboardActions.setKeyboardActions(context, _buildConfig(context));
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      focusNode: focusNode,
      cursorColor: Colors.pink,
      keyboardAppearance: Brightness.light,
      keyboardType: TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: widget.labelText,
      ),
      inputFormatters: [UsNumberTextInputFormatter()],
    );
  }
}
