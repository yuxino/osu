import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:osu/widgets/decimal-input.dart';

class OsuPage extends StatefulWidget {
  OsuPage({Key key}) : super(key: key);

  @override
  _OsuPageState createState() => _OsuPageState();
}

class _OsuPageState extends State<OsuPage> {
  bool flag = false;

  final verticalDirection = {
    false: VerticalDirection.down,
    true: VerticalDirection.up
  };

  void _toggleFlag() {
//    setState(() {
//      flag = flag ? false : true;
//    });

    _showNotionalFlag();
  }

  void _showNotionalFlag() {
    showModalBottomSheet(
        context: context,
        builder: (BuildContext context) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: Text(
                  '🇺🇸',
                  style: TextStyle(fontSize: 25),
                ),
                title: Text('美国'),
                subtitle: Text('hello'),
              ),
              ListTile(
                leading: Text(
                  '🇨🇳',
                  style: TextStyle(fontSize: 25),
                ),
                title: Text('中国'),
                subtitle: Text('hello'),
              ),
              ListTile(
                leading: Text(
                  '🇨🇳',
                  style: TextStyle(fontSize: 25),
                ),
                title: Text('中国'),
                subtitle: Text('hello'),
              ),
              ListTile(
                leading: Text(
                  '🇫🇷',
                  style: TextStyle(fontSize: 25),
                ),
                title: Text('法国'),
                subtitle: Text('hello'),
              )
            ],
          );
        });
  }

  @override
  Widget build(BuildContext context) {
    Widget _firstInput = Container(
        child: Column(
      children: <Widget>[
        DecimalInput(
          labelText: 'CNY',
        )
      ],
    ));

    Widget _exChangeIcon = Container(
      padding: EdgeInsets.symmetric(vertical: 30),
      child: IconButton(
        icon: Icon(Icons.arrow_forward_ios),
        onPressed: _toggleFlag,
      ),
    );

    Widget _secondInput = Container(
        child: Column(
      children: <Widget>[
        DecimalInput(
          labelText: 'JPY',
        )
      ],
    ));

    return Center(
      child: UnconstrainedBox(
        child: Container(
          width: MediaQuery.of(context).size.width,
          padding: EdgeInsets.all(35),
          child: Column(
            verticalDirection: verticalDirection[flag],
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
