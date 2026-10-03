// Builds Update-LefthyTools.cmd: the one file players need. It's a batch/PowerShell hybrid:
// cmd.exe sees "<# :" as a label and runs only the batch header, which hands the whole file to
// PowerShell; PowerShell sees "<# ... #>" as a comment and runs the rest, which is install.ps1.
// install.ps1 stays the source; `npm test` fails if the .cmd is out of date.
//   npm run build-installer
const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "..");

const HEADER = [
  "<# : LefthyTools installer for WoW: Forever - double-click to install or update",
  "@echo off",
  "rem One standalone file: everything after this batch part is install.ps1 (PowerShell). It downloads",
  "rem the latest LefthyTools from https://github.com/marcvef/wow-lefthytools and installs it into",
  "rem WoW: Forever's Interface\\AddOns folder. Settings (WTF folder) are kept.",
  "setlocal",
  "title LefthyTools",
  'set "LEFTHYTOOLS_INSTALLER=%~f0"',
  'set "LEFTHYTOOLS_INSTALLER_DIR=%~dp0"',
  'powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& ([ScriptBlock]::Create([IO.File]::ReadAllText($env:LEFTHYTOOLS_INSTALLER))) %*"',
  "echo.",
  "pause",
  "exit /b",
  "#>",
];

function build() {
  // "#>" ends PowerShell's comment block: only the header's last line may contain it.
  if (HEADER.slice(0, -1).some((line) => line.includes("#>"))) {
    throw new Error("the batch header must not contain #> before its last line");
  }
  const script = fs.readFileSync(path.join(root, "install.ps1"), "utf8").replace(/\r\n/g, "\n");
  if (/[^\x00-\x7f]/.test(script)) {
    throw new Error("install.ps1 must be plain ASCII (cmd.exe reads the .cmd in the console code page)");
  }
  return (HEADER.join("\n") + "\n" + script).replace(/\n/g, "\r\n");
}

module.exports = { build, target: path.join(root, "Update-LefthyTools.cmd") };

if (require.main === module) {
  fs.writeFileSync(module.exports.target, build());
  console.log("wrote " + path.relative(root, module.exports.target));
}
