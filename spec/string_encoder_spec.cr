require "./spec_helper"
require "../src/loader/string_encoder"

private def encode(source)
  String.build do |io|
    BakedFileSystem::StringEncoder.new(io) << source
  end
end

describe BakedFileSystem::StringEncoder do
  it "encodes trivial string" do
    encode("foo bar").should eq "foo bar"
  end

  it "escapes quote delimiter" do
    encode(%(foo")).should eq %(foo\\")
  end

  it "escapes interpolation" do
    encode("foo\#{bar}").should eq "foo\\#\\{bar}"
  end

  it "escapes macro delimiters" do
    encode("foo{% bar %}").should eq "foo\\{% bar %}"
  end

  it "escapes control characters" do
    encode("\b\e\f\n\r\t\v").should eq "\\b\\e\\f\\n\\r\\t\\v"
  end

  it "escapes escape character" do
    encode("\\n").should eq "\\\\n"
  end

  it "encodes unicode" do
    encode("\u{1F48E}").should eq "\\xF0\\x9F\\x92\\x8E"
    encode("💎").should eq "\\xF0\\x9F\\x92\\x8E"
  end
end
