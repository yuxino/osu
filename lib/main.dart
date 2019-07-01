import "package:flutter/material.dart";
import "package:keyboard_actions/keyboard_actions.dart";
import "package:osu/pages/osu.dart";

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: "Flutter Demo",
        theme: ThemeData(
          primarySwatch: Colors.blue,
        ),
        home: Scaffold(
          appBar: AppBar(
            title: Text("Osu"),
          ),
          body: FormKeyboardActions(child: OsuPage()),
        ));
  }
}
