import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:osu/constants/country-code.dart';

class Country extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: COUNTRY_CODE.length,
      itemBuilder: (context, index) {
        final item = COUNTRY_CODE[index];
        return ListTile(
          leading: Container(
            width: 50,
            child: Text(
              item['emoji'],
              style: TextStyle(fontSize: 25),
              textAlign: TextAlign.center,
            ),
          ),
          title: Text(item['country']),
          subtitle: Text(item['code']),
          onTap: () {
            print(item);
          },
        );
      },
    );
  }
}
