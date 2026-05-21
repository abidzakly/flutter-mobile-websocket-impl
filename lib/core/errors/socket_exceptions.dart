// lib/core/errors/socket_exceptions.dart
//
// Custom exception classes untuk error handling yang granular.
// Setiap tipe error memiliki class sendiri sehingga catch block
// dapat menangani masing-masing secara spesifik.

/// Base class untuk semua socket exception
abstract class SocketException implements Exception {
  final String message;
  const SocketException(this.message);

  @override
  String toString() => '${runtimeType}: $message';
}

/// Gagal membangun koneksi (network unreachable, server down, dsb)
class SocketConnectionException extends SocketException {
  const SocketConnectionException(super.message);
}

/// Mencoba kirim/terima tapi belum konek
class SocketNotConnectedException extends SocketException {
  const SocketNotConnectedException(super.message);
}

/// Server tidak merespons dalam waktu yang ditentukan
class SocketTimeoutException extends SocketException {
  const SocketTimeoutException(super.message);
}

/// Server mengembalikan respons error (type: ERROR)
class SocketServerException extends SocketException {
  const SocketServerException(super.message);
}

/// JSON tidak valid / tidak dapat di-parse
class SocketParseException extends SocketException {
  const SocketParseException(super.message);
}