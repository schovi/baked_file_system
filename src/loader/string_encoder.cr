# This class acts as an IO wrapper that encodes a byte stream
# as content for a string literal in Crystal code.
#
# It works similiar to `String.dump_unquoted` but operates on bytes instead of
# unicode characters and acts as an `IO`, so it doesn't need to allocate all
# data in memory.
class BakedFileSystem::StringEncoder < IO
  def initialize(@io : IO)
  end

  def self.open(io : IO, &)
    encoder = new(io)
    yield encoder ensure encoder.close
  end

  def read(slice : Bytes)
    raise "Can't read from StringEncoder"
  end

  # Encodes binary data as Crystal string literal.
  # Escapes special characters: ", #, \, {
  # Converts control characters to escape sequences.
  # Non-printable bytes become hex escapes (\xNN).
  def write(slice : Bytes) : Nil
    slice.each do |byte|
      case byte.chr
      when '"', '#', '\\', '{'
        @io << '\\'
        @io.write_byte byte
      when '\b'
        @io << "\\b"
      when '\t'
        @io << "\\t"
      when '\n'
        @io << "\\n"
      when '\v'
        @io << "\\v"
      when '\f'
        @io << "\\f"
      when '\r'
        @io << "\\r"
      when '\e'
        @io << "\\e"
      else
        if byte >= 32 && byte < 127
          @io.write_byte byte
        else
          @io << "\\x"
          @io << '0' if byte < 0x10_u8
          byte.to_s(@io, 16, upcase: true)
        end
      end
    end
  end
end
