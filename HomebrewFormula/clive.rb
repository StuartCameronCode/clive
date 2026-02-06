class Clive < Formula
  desc "macOS menu bar app that displays Claude Code usage statistics at a glance"
  homepage "https://github.com/StuartCameronCode/clive"
  url "https://github.com/StuartCameronCode/clive/releases/download/v1.0.6/Clive-1.0.6.zip"
  version "1.0.6"
  sha256 "9d70de26bd1930ee118515de97c035f73a69027ea26f0418344686e2340a2266"

  depends_on :macos

  def install
    prefix.install "Clive.app"
  end

  def caveats
    <<~EOS
      Clive has been installed to:
        #{prefix}/Clive.app

      To use Clive, you can either:
        1. Open it directly: open #{prefix}/Clive.app
        2. Create a symlink to /Applications:
            ln -s #{prefix}/Clive.app /Applications/Clive.app

      Note: Clive requires the Claude Code CLI to be installed at:
        /opt/homebrew/bin/claude

      You can add Clive to Login Items in System Settings to start it automatically.
    EOS
  end

  test do
    assert_predicate prefix/"Clive.app/Contents/MacOS/clive", :exist?
  end
end
