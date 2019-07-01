import "package:flutter/cupertino.dart";
import "package:flutter/material.dart";
import "package:keyboard_actions/keyboard_actions.dart";
import "package:osu/utils/textField-formatter.dart";

List<KeyboardAction> actions = [];

class DecimalInput extends StatefulWidget {
  final bool enable;
  final String text;
  final String icon;
  final String hintText;
  final Function prefixOnPress;
  final ValueChanged<String> onChanged;
  final TextEditingController controller;

  DecimalInput(
      {Key key,
      this.text,
      this.icon,
      this.prefixOnPress,
      this.hintText,
      this.enable,
      this.onChanged,
      this.controller})
      : super(key: key);

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

  Widget _buildPrefixIcon() {
    return Container(
        width: 100,
        child: IconButton(
            icon: Row(
              children: <Widget>[
                Container(
                  width: 50,
                  child: Text(
                    widget.icon,
                    style: TextStyle(fontSize: 25),
                  ),
                ),
                Text(widget.text)
              ],
            ),
            onPressed: () {
              widget.prefixOnPress();
            }));
  }

  @override
  Widget build(BuildContext context) {
    var enable = widget.enable;
    return Theme(
      data: enable == false
          ? Theme.of(context).copyWith(splashColor: Colors.transparent)
          : ThemeData(),
      child: TextField(
        focusNode: focusNode,
        cursorColor: Colors.pink,
        keyboardAppearance: Brightness.light,
        keyboardType: TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
            prefixIcon: _buildPrefixIcon(), hintText: widget.hintText),
        inputFormatters: [UsNumberTextInputFormatter()],
        onChanged: widget.onChanged,
        controller: widget.controller,
        enableInteractiveSelection: enable,
        style: TextStyle(),
        onTap: () {
          if (enable == false) {
            focusNode.unfocus();
          }
        },
      ),
    );
  }
}
