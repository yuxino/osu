import "package:flutter/cupertino.dart";
import "package:osu/widgets/decimal-input.dart";

// ignore: must_be_immutable
class Input extends StatefulWidget {
  var country = {"code": "", "emoji": ""};
  final showCountry;
  final hintText;
  final bool enable;
  final ValueChanged<String> onChanged;

  Input(
      {Key key,
      this.country,
      this.showCountry,
      this.hintText,
      this.enable,
      this.onChanged})
      : super(key: key);

  @override
  _InputState createState() => _InputState();
}

class _InputState extends State<Input> {
  void changeCountry(_country) {
    this.setState(() {
      widget.country = _country;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        DecimalInput(
            enable: widget.enable,
            text: widget.country["code"],
            icon: widget.country["emoji"],
            prefixOnPress: () {
              widget.showCountry(changeCountry);
            },
            hintText: widget.hintText,
            onChanged: widget.onChanged),
      ],
    );
  }
}
