module BakedFileSystem
  module Loader
    class ByteCounter < IO
      property count : Int64 = 0

      def initialize(@io : IO)
      end

      def read(slice : Bytes)
        @io.read(slice)
      end

      def write(slice : Bytes) : Nil
        @count += slice.size
        @io.write(slice)
      end
    end
  end
end
