part of TCP_implement.transmit;

String _getStringIp(List<int> ip) {
  StringBuffer sb = new StringBuffer();
  for (int i = 0, len = ip.length; i < len; i++) {
    sb.write(ip[i]);
    if (i != len -1) {
      sb.write('.');
    }
  }
  return sb.toString();
}

List<int> _parseIp(String ip) {
  List<int> ipNumbers = new List();
  int start = 0;
  int end = -1;
  while(true) {
    end = ip.indexOf('.', start);
    if (end != -1) {
      ipNumbers.add(int.parse(ip.substring(start, end)));
      start = end + 1;
    } else {
      ipNumbers.add(int.parse(ip.substring(start)));
      break;
    }
  }
  return ipNumbers;
}