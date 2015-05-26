library TCP_implement.agent;

import 'dart:io';
import 'dart:math';
import 'dart:async';
import 'util/config.dart';
import 'package:TCP_Implement/TCP_transmisson.dart' show Packet;

void main(List<String> args) {
  Random random = new Random(new DateTime.now().millisecondsSinceEpoch);
  int packageNum = 0;
  int dropNum = 0;
  
  //bind UDP socket
  RawDatagramSocket.bind(InternetAddress.ANY_IP_V4, agentPort)
  .then((RawDatagramSocket socket) {
    print('agent ready to receive on ${socket.address.address}:${socket.port}');
    print('');//chechge line
    
    //listen to datagram transfer
    StreamSubscription socketListen;
    socketListen = socket.listen((RawSocketEvent evt) {
      //receive datagram
      while(true) {
        Datagram datagram = socket.receive();
        if (datagram == null) return;
        
        Packet packet = new Packet.from(datagram.data);
        // to check the received data type
        if (packet.type == Packet.PSH) {
          packageNum++;
          print('get  data #${packet.sequenceN}');
          if(random.nextDouble() < 0.1) {  //drop the package
            dropNum++;
            print('drop data #${packet.sequenceN}, loss rate = ${dropNum/packageNum}');
          } else {  //pass
            socket.send(packet.datagram, new InternetAddress(packet.targetIp), packet.targetPort);
            print('fwd  data #${packet.sequenceN}, loss rate = ${dropNum/packageNum}');
          }
          
        } else if (packet.type == Packet.ACK) {  //just pass ACK
          print('get  ack  #${packet.sequenceN}');
          print('fwd  ack  #${packet.sequenceN}');
          socket.send(packet.datagram, new InternetAddress(packet.targetIp), packet.targetPort);
        } else if(packet.type == Packet.FIN) { //pass FIN
          print('get  fin  #${packet.sequenceN}');
          print('fwd  fin  #${packet.sequenceN}');
          socket.send(packet.datagram, new InternetAddress(packet.targetIp), packet.targetPort);
          socketListen.cancel();
        }
      }
    });
  });
}


