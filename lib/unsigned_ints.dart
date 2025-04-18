class UnsignedByte {
  UnsignedByte(this.byte) {
    if (byte < 0 || byte > 255) {
      throw ArgumentError("byte must be in interval [0, 255]");
    }
  }

  int byte;

  UnsignedByte operator +()
}
