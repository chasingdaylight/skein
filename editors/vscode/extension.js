// The extension's code: it makes the `skein` program that the package
// carries (bin/) available in VS Code's terminals, and says which one is
// in use. The highlighting needs none of this; it is the grammar's.
//
// Plain JavaScript without dependencies, so that nothing is built or
// bundled for it.
'use strict'

const vscode = require('vscode')
const fs = require('fs')
const path = require('path')
const { execFile } = require('child_process')

const programName = process.platform === 'win32' ? 'skein.exe' : 'skein'

/** The skein to use: the one `skein.path` names, else the one in the package; null when there is none. */
function findProgram(context) {
  const configured = vscode.workspace.getConfiguration('skein').get('path', '').trim()
  if (configured) return fs.existsSync(configured) ? configured : null
  const bundled = path.join(context.extensionPath, 'bin', programName)
  return fs.existsSync(bundled) ? bundled : null
}

/** Puts the directory of the program first on the PATH of the terminals opened from now on. */
function updateTerminals(context) {
  const env = context.environmentVariableCollection
  env.clear()
  const program = findProgram(context)
  if (!program) return
  env.description = 'Adds skein to the PATH'
  env.prepend('PATH', path.dirname(program) + path.delimiter)
}

function showVersion(context) {
  const program = findProgram(context)
  if (!program) {
    const configured = vscode.workspace.getConfiguration('skein').get('path', '').trim()
    vscode.window.showWarningMessage(configured
      ? `skein: there is no file '${configured}' (the setting skein.path).`
      : 'skein: this package of the extension carries no skein program for this platform. Install skein and set skein.path, or put it on the PATH.')
    return
  }
  execFile(program, ['version'], { timeout: 10000 }, (error, stdout) => {
    if (error) {
      vscode.window.showErrorMessage(`skein: could not run '${program}': ${error.message}`)
      return
    }
    vscode.window.showInformationMessage(`skein ${stdout.trim()} (${program})`)
  })
}

function activate(context) {
  updateTerminals(context)
  context.subscriptions.push(
    vscode.workspace.onDidChangeConfiguration((event) => {
      if (event.affectsConfiguration('skein.path')) updateTerminals(context)
    }),
    vscode.commands.registerCommand('skein.showVersion', () => showVersion(context)),
  )
}

function deactivate() {}

module.exports = { activate, deactivate }
