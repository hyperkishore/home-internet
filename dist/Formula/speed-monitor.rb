class SpeedMonitor < Formula
  desc "Internet speed monitoring with central dashboard aggregation"
  homepage "https://github.com/kishore/speed-monitor"
  url "https://github.com/kishore/speed-monitor/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "PLACEHOLDER_SHA256"
  license "MIT"

  depends_on "speedtest-cli"

  def install
    bin.install "bin/speed-monitor"
  end

  def post_install
    ohai "Speed Monitor installed!"
    ohai "Run 'speed-monitor setup' to configure"
  end

  def caveats
    <<~EOS
      To get started:
        speed-monitor setup

      To start automatic monitoring:
        speed-monitor start

      To view status:
        speed-monitor status

      To open the local dashboard:
        speed-monitor dashboard
    EOS
  end

  test do
    assert_match "speed-monitor", shell_output("#{bin}/speed-monitor --version")
  end
end
