library TCP_implement.transmit;

import 'dart:io';
import 'dart:async';

part 'src/util.dart';

const TIMEOUT = const Duration(milliseconds: 3000);
const int _datalen = 900;
const String _agentIp = '127.0.0.1';
const int _agentPort = 8092;

class TCPTransmission {
  static const int SENDER = 0;
  static const int RECVER = 1; 
  
  int type; //present sender/receiver
  
  String selfIp;
  int selfPort;
  String targetIp;
  int targetPort;
  RawDatagramSocket _socket;
  StreamSubscription _listener;
  File _file;
  /// List<int> of data, initial in [_sendFile]
  List<int> _fileData;
  
  //for sender
  ///the smallest sn in current window
  int _current = 0;
  int _last = -1;
  /// whether the sent datagrams in current window received ack,
  /// initailize every new window; 
  List<bool> _sent; 
  /// the timer of the sent datagrams in current window, same as above                  
  List<Timer> _timers; 
  /// to check whether all packets in window recv ack
  bool get _allWinRecv {
    for (bool recv in _sent)
      if(recv == false)
        return false;
    return true;
  }
  CongectionControl _congection;
  
  /// for compute _lastestSn , store receive ackN times, initial in [_sendFile]
  List<bool> _allSent; 
  /// last number of the sequence begining with 1 of sn of received ack
  int get _lastestSn {
    int i = 0;
    for (int len = _allSent.length; i < len ;i++) {
      if (_allSent[i] == false)
        return i - 1;
    }
    return i;
  }
  
  //for receiver
  Buffer _buffer;
  /// whether is write buffer to fill
  bool _flushing = false;
  
  ///init Tcp transmission with [type](sender/receiver),
  ///and self port, target port & ip 
  static Future<TCPTransmission> initTCPTransmission(int type, int selfPort, String targetIp, int tartgetPort) {
    TCPTransmission transmission = new TCPTransmission._(type, selfPort, targetIp, tartgetPort);
    return RawDatagramSocket.bind(InternetAddress.ANY_IP_V4, selfPort)
    .then((_){
      //init transmitssion
      transmission._socket = _;
//      transmission.selfIp = transmission._socket.address.address;
      transmission.selfIp = "127.0.0.1";
      transmission._congection = new CongectionControl();
      transmission._buffer = new Buffer(32);
      return new Future.value(transmission);
    });
  }
  
  /// a static funstion,
  /// separate hole file to datgram and send them with reliablity
  Future sendFile(File file)=> _sendFile(file);
  
  /// a static function,
  /// to handle buffer and receive file
  void receiveFile(File file) => _receiveFile(file);
  
  /*-------------------------private functions---------------------------*/
  /// construction of TCPTransmission, only sender need [targetIp],[targetPort]
  TCPTransmission._(this.type, this.selfPort, [this.targetIp, this.targetPort]);
  
  Future _sendFile(File file) {
    _file = file;
    return file.readAsBytes()
    .then((_) {
      _fileData = _;
      _allSent = new List.filled((_fileData.length/_datalen).ceil(), false);
      _startListener();
      _sendWindow();
    });
  }
  
  void _receiveFile(File file) {
    _file = file;
    _startListener();
  }
  
  void _startListener() {
      _listener = _socket.listen(type == SENDER? _senderHandler: _recverHandler);
  }
  
  void _senderHandler(RawSocketEvent evt) {
    while(true) {
      //recive data, if there is no data, return, else parse recieves datagram
      Datagram datagram = _socket.receive();
      if (datagram == null) return;
      Packet packet = new Packet.from(datagram.data); // parse the datagram
        
      if (packet.type != Packet.ACK) {
        continue;
      }// ingnore datagam whose type != ack
      // if ack sn is not in current window, ignore it
      if (!_inCurrentWindow(packet.sequenceN)) {
        continue;
      }
      //receive ackSN
      //1.cancel Timer, 2.falg _sent, 3. flag _allSent(for move current)
      print('recv  ack  #${packet.sequenceN}');
      int index = packet.sequenceN - _current - 1;
      _timers[index].cancel();
      _sent[index] = true;
      _allSent[packet.sequenceN - 1] = true;
      
      //check whether current window is done
      //if done, 1.set current to the position after window size,
      //2. adjust _congection, 3. send next window
      if (_allWinRecv) {
        _current += _congection.window;
        if (_current >= _allSent.length) { 
          _closeConnection();
        } else {
          _congection.increase();
          _sendWindow();
        }
      }
    }
  }
  
  void _recverHandler(RawSocketEvent evt) {
    
    while(true) {
      //recive data, if there is no data, return, else parse recieves datagram
      Datagram datagram = _socket.receive();
      if (datagram == null) return;
      Packet packet = new Packet.from(datagram.data); // parse the datagram
      if (packet.type == Packet.FIN) { //close the connection
        if (!_buffer.isEmpty) {
          _file.writeAsBytesSync(_buffer.popAll(), mode: FileMode.APPEND);
        }
        _listener.cancel();
        return;
      }

      if (packet.type == Packet.PSH) {//push to buffer. if return ture, push succefully
        if (targetPort == null) { //inital sender address when recv first packet
          targetIp = packet.selfIp;
          targetPort = packet.selfPort;
        }
        
        int n = _buffer.push(packet.data, packet.sequenceN);
        if (n == 1) {
          print('recv  data #${packet.sequenceN}');
          _socket.send(_createAck(packet.sequenceN).datagram, new InternetAddress(_agentIp), _agentPort);
          print('send  ack  #${packet.sequenceN}');
        } else if (n == 0) { //already recv
          print('ignore data #${packet.sequenceN}');
          _socket.send(_createAck(packet.sequenceN).datagram, new InternetAddress(_agentIp), _agentPort);
          print('send  ack  #${packet.sequenceN}');
        } else { //drop(out of current buffer)
          //if buffer is full, drop packets, and if not flushing, flush buffer into file
          print('drop  data #${packet.sequenceN}');
          if (_buffer.isFull) {
            _file.writeAsBytesSync(_buffer.popAll(), mode: FileMode.APPEND);
            continue;
          }
        }
      }
    }
    return;
  }
  
  ///send the packsges in window, and set time out for each packet
  ///if timeout, set window, and send again;
  void _sendWindow() {
    _sent = new List.filled(_congection.window, false);
    _timers = new List(_congection.window);
    for (int i = 0; i < _congection.window; i++) {
      if ((_current + i) > _allSent.length - 1) {
        _timers[i] = new Timer(TIMEOUT, () {}); //avoid cancel null object
        _sent[i] = true; //asume receive ack, avoid detect error
        continue;
      } else {
        if ((_current + i) == _allSent.length - 1) {//last datagram (dont give sublist end)
          _socket.send(new Packet(Packet.PSH, _current + i + 1, targetIp, targetPort, selfIp, selfPort, 
            _fileData.sublist(_datalen * (_current + i))).datagram,
            new InternetAddress(_agentIp), _agentPort);
        } else {
          _socket.send(new Packet(Packet.PSH, _current + i + 1, targetIp, targetPort, selfIp, selfPort, 
            _fileData.sublist(_datalen * (_current + i), _datalen * (_current + i + 1))).datagram,
            new InternetAddress(_agentIp), _agentPort);
        } 
        if ((_current + i) > _last)
          print('send  data #${_current + i + 1}, winSize = ${_congection.window}');
        else //already send
          print('resend  data #${_current + i + 1}, winSize = ${_congection.window}');
        if ((_current + i) > _last)
          _last = _current + i;
        //if timeout, cancel all timer, adjust [_congection] and [_current], send new window ;
        _timers[i] = new Timer(TIMEOUT, () {
          print('time  out, threshold = ${_congection.ssthreshold}');
          _timers.forEach((_)=>_.cancel());
          _current = _lastestSn + 1; //the next part of the last part receive ack
          _congection.setAsLoss();
          _sendWindow();
        });
      }
    }
  }
  
  void _closeConnection() {
    //send FIN, cancel listener, return
    _socket.send(new Packet(Packet.FIN, 0, targetIp, targetPort, selfIp, selfPort, []).datagram,
        new InternetAddress(_agentIp), _agentPort);
    _listener.cancel();
  }
  
  Packet _createAck(int sequenceNumber) {
    return new Packet(Packet.ACK, sequenceNumber, targetIp, targetPort, selfIp, selfPort, []);
  }
  
  bool _inCurrentWindow(int sn) {
    if (sn <= _current || sn > _current + _congection.window)
      return false;
    return true;
  }
}

class Packet {
  static const int ACK = 0;
  static const int FIN = 1;
  static const int PSH = 2;
  
  static const int _TYPE_POS = 0;
  static const int _SN_POS_1 = 1;
  static const int _SN_POS_2 = 2;
  static const int _SN_POS_3 = 3;
  static const int _TARGET_IP_POS = 4;
  static const int _TARGET_PORT_D_POS = 8;
  static const int _TARGET_PORT_R_POS = 9;
  static const int _SELF_IP_POS = 10;
  static const int _SELF_PORT_D_POS = 14;
  static const int _SELF_PORT_R_POS = 15;
  static const int _DATA_BEGIN = 16;
  
  List<int> datagram;
  List<int> get data => datagram.sublist(_DATA_BEGIN);
  int get type => datagram[_TYPE_POS];
  int get sequenceN => datagram[_SN_POS_1] * 10000 + datagram[_SN_POS_2] * 100 + datagram[_SN_POS_3];
  String get targetIp => _getStringIp(datagram.sublist(_TARGET_IP_POS, _TARGET_IP_POS + 4));
  int get targetPort => datagram[_TARGET_PORT_D_POS] * 100 + datagram[_TARGET_PORT_R_POS];
  String get selfIp => _getStringIp(datagram.sublist(_SELF_IP_POS, _SELF_IP_POS + 4));
  int get selfPort => datagram[_SELF_PORT_D_POS]* 100 + datagram[_SELF_PORT_R_POS];
  
  Packet(int type, int sequenceNumber, String targetIp, int targetPort, String selfIp, int selfPort, List<int> data) {
    datagram = new List();
    datagram.add(type);//0
    datagram.add(sequenceNumber~/10000);//__XXXX
    datagram.add((sequenceNumber%10000)~/100);//XX__XX
    datagram.add(sequenceNumber%100);//XXXX__
    datagram.addAll(_parseIp(targetIp));
    datagram.add(targetPort~/100);
    datagram.add(targetPort%100);
    datagram.addAll(_parseIp(selfIp));
    datagram.add(selfPort~/100);
    datagram.add(selfPort%100);
    datagram.addAll(data);
  }
  
  Packet.from(this.datagram);
}

class CongectionControl {
  int  window = 1;
  int ssthreshold = 16;
  
  increase() {
    if (window >= ssthreshold)
      window += 1;
    else
      window *= 2;
  }
  
  setAsLoss() {
    ssthreshold = window ~/2;
    window = 1;
  }
  
  setAsTriDuplicate() {
    ssthreshold = (window / 2).ceil();
    window = ssthreshold;
  }
  
  String toString() => '($window, $ssthreshold)';
}

class Buffer {
  int size;
  int _filled = 0;//to determine whether is full
  int _round = 0;//to determine whether packet should save 
  List<List<int>> _buffer;
  List<bool> _indexes;
  
  bool get isFull => _filled == size;
  bool get isEmpty => _filled == 0;
  
  Buffer(this.size) {
    _buffer = new List.filled(size, new List());
    _indexes = new List.filled(size, false);
  }
  
  ///push data to buffer, 
  ///return -1/0/1 when out of buffer/ already recv/accept data
  int push(List<int> data, int sn) {
    // only recieve current sn ~ sn + size
    if (sn <= _round * size)
      return 0;
    else if (sn > (_round + 1 )* size)
      return -1;
    int index = (sn - 1) % size;
    if (_indexes[index]) // already recv
      return 0;
    _buffer[index] = data;
    _indexes[index] = true;
    _filled++;
    return 1;
  }
  
  List<int> popAll() {
    List fileData = new List();
    for (List<int> data in _buffer) {
      fileData.addAll(data);
    }
    print('flush');
    _filled = 0;
    for (int i = 0; i < size; i++)
      _indexes[i] = false;
    _round++;
    return fileData;
  }
}