# Homebrew formula for afar-cli. This repository doubles as its tap:
#   brew tap johannesreich1/afar-cli https://github.com/johannesreich1/afar-cli
#   brew install johannesreich1/afar-cli/afar-cli   (the full name; Homebrew refuses short names from other taps)
# For a new release, tag it, then update url and sha256 here.
class AfarCli < Formula
  desc "Keep Claude Code Remote Control running in the background"
  homepage "https://github.com/johannesreich1/afar-cli"
  url "https://github.com/johannesreich1/afar-cli/archive/refs/tags/v0.4.0.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  license "MIT"
  head "https://github.com/johannesreich1/afar-cli.git", branch: "main"

  depends_on :macos

  def install
    bin.install "bin/afar-cli"
  end

  def caveats
    <<~EOS
      Serve a project folder in the background:
        afar-cli add ~/path/to/project

      Services keep running after `brew uninstall`. Remove them first with:
        afar-cli remove --all
    EOS
  end

  test do
    assert_match "afar-cli #{version}", shell_output("#{bin}/afar-cli version")
  end
end
