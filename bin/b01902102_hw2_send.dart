library TCP_implement.sender;

import 'dart:io';

import 'util/config.dart';
import 'package:TCP_Implement/TCP_transmisson.dart';

void main(List<String> args) {
  File file = new File(filePath);
  TCPTransmission.initTCPTransmission(TCPTransmission.SENDER, senderPort, receiverIP, receiverPort)
  .then((TCPTransmission transmission) {
    return transmission.sendFile(file);
  })
  .catchError((e, st){
      print('Error: $e${st == null?"":", $st"}');
  });
}