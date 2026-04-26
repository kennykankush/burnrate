cask "burnrate" do
  version "0.1.0"
  sha256 "963832f23445bc79846d770c4d47d4b3c50ec1ac22d13f6d06ffafe9671f366b"

  url "https://github.com/kennykankush/burnrate/releases/download/v#{version}/burnrate-#{version}.zip"
  name "burnrate"
  desc "Menu bar tracker for Claude Code and Codex usage, costs, and limits"
  homepage "https://burnrate.fyi"

  livecheck do
    url :url
    strategy :github_latest
  end

  app "burnrate.app"

  # First-launch UX warning for users on unsigned/Apple-Development builds.
  # Once burnrate ships with a Developer ID Application cert + notarisation,
  # delete this caveats block.
  caveats <<~EOS
    burnrate is currently signed with an Apple Development certificate
    (not yet notarised). On first launch, macOS will refuse to open it.

    To open it:
      1. Right-click burnrate in /Applications
      2. Choose "Open"
      3. Click "Open" in the warning dialog

    macOS remembers this choice — subsequent launches work normally.
  EOS

  zap trash: [
    "~/Library/Application Support/burnrate",
    "~/Library/Caches/burnrate",
    "~/Library/Preferences/fyi.burnrate.app.plist",
    "~/Library/Saved Application State/fyi.burnrate.app.savedState",
  ]
end
