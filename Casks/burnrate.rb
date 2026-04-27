cask "burnrate" do
  version "0.1.2"
  sha256 "dd010811973af87cc098758b56f525a8f3a1ec830fb5ee00ded14df23fd8831c"

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
    (not yet notarised). On first launch, macOS will refuse to open it
    and show "Apple could not verify burnrate is free of malware".

    To open it:
      1. Click "Done" on the dialog (NOT "Move to Trash")
      2. Open System Settings, then Privacy and Security
      3. Scroll down, find the burnrate entry, click "Open Anyway"
      4. Authenticate with Touch ID or your password
      5. Click "Open" on the new confirmation dialog

    macOS remembers this choice. Future launches work normally.
  EOS

  zap trash: [
    "~/Library/Application Support/burnrate",
    "~/Library/Caches/burnrate",
    "~/Library/Preferences/fyi.burnrate.app.plist",
    "~/Library/Saved Application State/fyi.burnrate.app.savedState",
  ]
end
