require "./spec_helper"

describe BakedFs do
  it "get correct file name" do
    file = Storage.get("images/pixel.png")
    file.name.should eq("pixel.png")
  end

  it "get correct file content" do
    file = Storage.get("images/pixel.png")
    content = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABAQMAAAAl21bKAAAAA1BMVEX/TQBc\nNTh/AAAAAXRSTlPM0jRW/QAAAApJREFUeJxjYgAAAAYAAzY3fKgAAAAASUVO\nRK5CYII=\n"

    file.content.should eq(content)
  end

  it "throws error on missing file" do
    # pp Storage.get("images/missing.file")
  end
end
