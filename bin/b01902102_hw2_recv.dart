library TCP_implement.receiver;

import 'dart:io';
import 'util/config.dart';
import 'package:TCP_Implement/TCP_transmisson.dart';

void main(List<String> args) {
  File file = new File('testR.txt');
  if (file.existsSync())
    file.deleteSync();
  file.createSync();
  TCPTransmission.initTCPTransmission(TCPTransmission.RECVER, receiverPort, null, null)
  .then((TCPTransmission transmission) {
    return transmission.receiveFile(file);
  })
  .catchError((e, st){
      print('Error: $e${st == null?"":", $st"}');
  });
}