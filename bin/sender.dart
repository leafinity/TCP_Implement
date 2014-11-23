library TCP_implement.sender;

import 'dart:io';
import 'dart:async';
import 'package:TCP_Implement/config.dart';

void main(List<String> args) {
  RawDatagramSocket.bind(InternetAddress.ANY_IP_V4, senderPort)
  .then((RawDatagramSocket socket) {
    print('start sending ending from ${socket.address.address}:${socket.port}');
    
    //send the datagram transform into List<int>
    socket.send('Hello from UDP land!\n'.codeUnits, 
      new InternetAddress(receiverIP), receiverPort);
  });
}