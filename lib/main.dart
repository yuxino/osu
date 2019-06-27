import 'package:flutter/material.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key}) : super(key: key);

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  bool flag = false;

  final verticalDirection = {
    false: VerticalDirection.up,
    true: VerticalDirection.down
  };

  final iconDirection = {
    false: Icons.arrow_back_ios,
    true: Icons.arrow_forward_ios
  };

  void _toggleFlag() {
    setState(() {
      flag = flag ? false : true;
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget body = UnconstrainedBox(
        child: Container(
      width: MediaQuery.of(context).size.width,
//      color: Colors.pink,
      child: Column(
        verticalDirection: verticalDirection[flag],
        children: <Widget>[
          Container(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Column(
                children: <Widget>[
                  TextField(
                    cursorColor: Colors.pink,
                    keyboardAppearance: Brightness.dark,
                    keyboardType: TextInputType.number,
//                    textInputAction: TextInputAction.go,
                    decoration: InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Password',
//                        counterText: "counterText",
                        prefixIcon: Icon(Icons.pregnant_woman),
                        counter: Text('asd')),
                  )
                ],
              )),
          IconButton(
            icon: Icon(iconDirection[flag]),
            onPressed: _toggleFlag,
          ),
          Container(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Column(
                children: <Widget>[Text('2')],
              )),
        ],
      ),
    ));

    return Scaffold(
      appBar: AppBar(
        title: Text('Hello world'),
      ),
      body: Center(
        child: body,
      ),
    );
  }
}
