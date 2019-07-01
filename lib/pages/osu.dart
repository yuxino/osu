import "package:flutter/cupertino.dart";
import "package:flutter/material.dart";
import "package:osu/constants/country-code.dart";
import 'package:osu/services/api.dart';
import 'package:osu/utils/debounce.dart';
import "package:osu/widgets/country-input.dart";
import "package:osu/widgets/country.dart";
import 'package:decimal/decimal.dart';

class OsuPage extends StatefulWidget {
  OsuPage({Key key}) : super(key: key);

  @override
  _OsuPageState createState() => _OsuPageState();
}

class _OsuPageState extends State<OsuPage> {
  var _firstInputState = COUNTRY_CODE[0];
  var _secondInputState = COUNTRY_CODE[1];
  var _cached = {};
  var _loading = false;
  var _firstController = TextEditingController(text: '');
  var _secondController = TextEditingController(text: '');

  final _debounce = Debounce(milliseconds: 0);

  final verticalDirection = {
    false: VerticalDirection.down,
    true: VerticalDirection.up
  };

  void _toggleFlag() {
    setState(() {
      final temp = _firstInputState;
      _firstInputState = _secondInputState;
      _secondInputState = temp;
      if (_firstController.text != "") {
        _computerConversion(_firstController.text);
      }
    });
  }

  void _setFirstInputState(item) {
    setState(() {
      _firstInputState = item;
      _computerConversion(_firstController.text);
    });
  }

  void _setSecondInputState(item) {
    setState(() {
      _secondInputState = item;
      _computerConversion(_firstController.text);
    });
  }

  void _loadingStart() {
    this.setState(() => {_loading = true});
    _secondController.text = '';
  }

  void _loadingEnd() {
    this.setState(() => {_loading = false});
  }

  Function _showCountry(String state) {
    return (Function callback) {
      showModalBottomSheet(
        context: context,
        builder: (builder) {
          return Country(
            callback: (item) {
              switch (state) {
                case "FIRST":
                  return _setFirstInputState(item);
                case "SECOND":
                  return _setSecondInputState(item);
              }
            },
          );
        },
      );
    };
  }

  _computerConversion(String text) async {
    final c1 = _firstInputState['code'];
    final c2 = _secondInputState['code'];
    final key = '$c1-$c2';
    Decimal rate;
    Decimal number;

    if (c1 == c2) {
      rate = Decimal.fromInt(1);
    } else {
      if (_cached[key] == null) {
        _loadingStart();
        final data = await getConversion(c1: c1, c2: c2);
        rate = Decimal.parse(data['data']['rate']);
        print(rate);
        _cached[key] = rate;
        _loadingEnd();
      } else {
        rate = _cached[key];
      }
    }
    number = text != "" ? Decimal.parse(text) : Decimal.fromInt(0);

    final String result = text != "" ? '${(number * rate)}' : '';
    _secondController.text = result;
  }

  @override
  Widget build(BuildContext context) {
    Widget _firstInput = CountryInput(
      country: _firstInputState,
      showCountry: _showCountry("FIRST"),
      hintText: "Input Money",
      onChanged: (text) {
        _debounce.run(() => _computerConversion(text));
      },
      controller: _firstController,
    );

    Widget _exChangeIcon = Container(
      padding: EdgeInsets.symmetric(vertical: 30),
      child: IconButton(
        icon: Icon(Icons.arrow_forward_ios),
        onPressed: _toggleFlag,
      ),
    );

    Widget _secondInput = CountryInput(
      enable: false,
      country: _secondInputState,
      showCountry: _showCountry("SECOND"),
      hintText: _loading ? "Getting Conversion ..." : "Output Money",
      controller: _secondController,
    );

    return Center(
      child: UnconstrainedBox(
        child: Container(
          width: MediaQuery.of(context).size.width,
          padding: EdgeInsets.all(35),
          child: Column(
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
