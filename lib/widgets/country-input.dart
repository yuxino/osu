import "package:flutter/cupertino.dart";
import "package:osu/widgets/decimal-input.dart";

// ignore: must_be_immutable
class CountryInput extends StatefulWidget {
  var country = {"code": "", "emoji": ""};
  final showCountry;
  final hintText;
  final bool enable;
  final ValueChanged<String> onChanged;
  final TextEditingController controller;

  CountryInput(
      {Key key,
      this.country,
      this.showCountry,
      this.hintText,
      this.enable,
      this.onChanged,
      this.controller})
      : super(key: key);

  @override
  _CountryInputState createState() => _CountryInputState();
}

class _CountryInputState extends State<CountryInput> {
  void changeCountry(_country) {
    this.setState(() {
      widget.country = _country;
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget input = DecimalInput(
        enable: widget.enable,
        text: widget.country["code"],
        icon: widget.country["emoji"],
        prefixOnPress: () {
          widget.showCountry(changeCountry);
        },
        hintText: widget.hintText,
        onChanged: widget.onChanged,
        controller: widget.controller);

    return Column(
      children: <Widget>[
        input,
      ],
    );
  }
}
