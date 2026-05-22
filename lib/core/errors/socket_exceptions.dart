// lib/core/errors/socket_exceptions.dart

/// Base class untuk semua socket exception
abstract class SocketException implements Exception {
  final String message;
  const SocketException(this.message);

  @override
  String toString() => '${runtimeType}: $message';
}

class SocketConnectionException extends SocketException {
  const SocketConnectionException(super.message);
}

class SocketNotConnectedException extends SocketException {
  const SocketNotConnectedException(super.message);
}

class SocketTimeoutException extends SocketException {
  const SocketTimeoutException(super.message);
}

class SocketServerException extends SocketException {
  const SocketServerException(super.message);
}

class SocketParseException extends SocketException {
  const SocketParseException(super.message);
}

class SocketAuthException extends SocketException {
  const SocketAuthException(super.message);
}
