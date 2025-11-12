import 'package:flutter/material.dart';
import 'pages/connect_page.dart';

void main() {
  runApp(const TransducerApp());
}

class TransducerApp extends StatelessWidget {
  const TransducerApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Transducer TCP',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const ConnectPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}