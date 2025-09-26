class Rgcidr < Formula
  desc "High-performance Zig library and CLI tool for filtering IPv4 and IPv6 addresses against CIDR patterns"
  homepage "https://github.com/yourusername/rgcidr"
  url "https://github.com/yourusername/rgcidr/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "SHA256_HASH_TO_BE_UPDATED"
  license "MIT"
  
  depends_on "zig" => :build

  def install
    system "zig", "build", "-Doptimize=ReleaseFast"
    bin.install "zig-out/bin/rgcidr"
  end

  test do
    # Test basic functionality
    assert_match version.to_s, shell_output("#{bin}/rgcidr --version 2>&1", 1)
    
    # Test IP filtering functionality
    (testpath/"test.txt").write("192.168.1.1\n10.0.0.1\n172.16.0.1\n")
    output = shell_output("#{bin}/rgcidr '192.168.0.0/16' #{testpath}/test.txt")
    assert_match "192.168.1.1", output
    refute_match "10.0.0.1", output
  end
end