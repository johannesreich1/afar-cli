# Homebrew formula for afar-rcd. This repository doubles as its tap:
#   brew tap johannesreich1/afar-rcd https://github.com/johannesreich1/afar-rcd
#   brew install afar-rcd
# For a new release, tag it, then update url and sha256 here.
class AfarRcd < Formula
  desc "Keep Claude Code Remote Control running in the background"
  homepage "https://github.com/johannesreich1/afar-rcd"
  url "https://github.com/johannesreich1/afar-rcd/archive/refs/tags/v0.2.0.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  license "MIT"
  head "https://github.com/johannesreich1/afar-rcd.git", branch: "main"

  depends_on :macos

  def install
    bin.install "bin/afar-rcd"
  end

  def caveats
    <<~EOS
      Serve a project folder in the background:
        afar-rcd add ~/path/to/project

      Services keep running after `brew uninstall`. Remove them first with:
        afar-rcd remove --all
    EOS
  end

  test do
    assert_match "afar-rcd #{version}", shell_output("#{bin}/afar-rcd version")
  end
end
