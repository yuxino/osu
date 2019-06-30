import "package:flutter/cupertino.dart";
import "package:flutter/material.dart";
import "package:osu/constants/country-code.dart";
import "package:osu/widgets/country-input.dart";
import "package:osu/widgets/country.dart";

class OsuPage extends StatefulWidget {
  OsuPage({Key key}) : super(key: key);

  @override
  _OsuPageState createState() => _OsuPageState();
}

class _OsuPageState extends State<OsuPage> {
  bool _flag = false;

  var _firstInputState = COUNTRY_CODE[0];
  var _secondInputState = COUNTRY_CODE[1];

  final verticalDirection = {
    false: VerticalDirection.down,
    true: VerticalDirection.up
  };

  void _toggleFlag() {
    setState(() {
      _flag = _flag ? false : true;
    });
  }

  void _setFirstInputState(item) {
    setState(() {
      _firstInputState = item;
    });
  }

  void _setSecondInputState(item) {
    setState(() {
      _secondInputState = item;
    });
  }

  Function _showCountry(String state) {
    return (Function callback) {
      showModalBottomSheet(
          context: context,
          builder: (builder) {
            return Country(callback: (item) {
              switch (state) {
                case "FIRST":
                  return _setFirstInputState(item);
                case "SECOND":
                  return _setSecondInputState(item);
              }
            });
          });
    };
  }

  @override
  Widget build(BuildContext context) {
    Widget _firstInput =
        Input(country: _firstInputState, showCountry: _showCountry("FIRST"));

    Widget _exChangeIcon = Container(
      padding: EdgeInsets.symmetric(vertical: 30),
      child: IconButton(
        icon: Icon(Icons.arrow_forward_ios),
        onPressed: _toggleFlag,
      ),
    );

    Widget _secondInput =
        Input(country: _secondInputState, showCountry: _showCountry("SECOND"));

    return Center(
      child: UnconstrainedBox(
        child: Container(
          width: MediaQuery.of(context).size.width,
          padding: EdgeInsets.all(35),
          child: Column(
            verticalDirection: verticalDirection[_flag],
            children: <Widget>[
              _firstInput,
              _exChangeIcon,
              _secondInput,
            ],
          ),
        ),
      ),
    );
  }
}
