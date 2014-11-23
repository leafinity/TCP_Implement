library TCP_implement.receiver;

import 'dart:io';
import 'dart:async';
import 'package:TCP_Implement/config.dart';

void main(List<String> args) {
  RawDatagramSocket.bind(InternetAddress.ANY_IP_V4, receiverPort)
  .then((RawDatagramSocket socket) {
    print('Datagram socket ready to receive on ${socket.address.address}:${socket.port}');
    
    //listen to datagram transfer
    socket.listen((RawSocketEvent evt){
      //receive datagram
      Datagram datagram = socket.receive();
      if (datagram == null) {
print('receive nothing!!');
        return;
      }
      //transform data, canse data was sent as a List<int>;
      //and remove any leading and trailing whitespace.
      String message = new String.fromCharCodes(datagram.data).trim(); //transfer from
      print('Datagram from ${datagram.address.address}:${datagram.port}: ${message}');
    });
  });
}