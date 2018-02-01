# This class acts as an IO wrapper that encodes a byte stream
# as content for a string literal in Crystal code.
#
# It works similiar to `String.dump_unquoted` but operates on bytes instead of
# unicode characters and acts as an `IO`, so it doesn't need to allocate all
# data in memory.
class BakedFileSystem::StringEncoder < IO
  def initialize(@io : IO)
  end

  def self.open(io : IO)
    encoder = new(io)
    yield encoder ensure encoder.close
  end

  def read(slice : Bytes)
    raise "Can't read from StringEncoder"
  end

  def write(slice : Bytes)
    slice.each do |byte|
      case byte
      when 34_u8, 35_u8, 92_u8, 123_u8
        # escape `"` (string delimiter), `#` (string interpolation), `\\` (escape character) and `{` (macro expression)
        @io << '\\'
        @io.write_byte byte
      when 32_u8..127_u8
        @io.write_byte byte
      when  8_u8 then @io << "\\b"
      when  9_u8 then @io << "\\t"
      when 10_u8 then @io << "\\n"
      when 11_u8 then @io << "\\v"
      when 12_u8 then @io << "\\f"
      when 13_u8 then @io << "\\r"
      when 27_u8 then @io << "\\e"
      else
        @io << "\\x"
        @io << '0' if byte < 0x10_u8
        byte.to_s(16, @io, upcase: true)
      end
    end
  end
end
