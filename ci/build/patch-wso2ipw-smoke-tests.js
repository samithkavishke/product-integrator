const fs = require('fs');
const path = require('path');

// The example comes from the caller rather than a list in here: the workflow's `example` matrix is the
// single source of truth for which ones exist. Hardcoding them here would let a new matrix entry go
// unpatched — the checks below only fire for names this script is told about, so that example would
// drive the old welcome page and fail in the UI instead of here.
const [, , examplesRoot, example] = process.argv;
if (!examplesRoot || !example) {
  throw new Error('Usage: node patch-wso2ipw-smoke-tests.js <wso2ipw-examples-directory> <example>');
}

// [from, to] pairs per example script; every `from` must be present. A script that the example
// does not ship is skipped, so 08-verify-icp.sh only applies to icp.
const replacements = {
  '02-create-integration.sh': [
    ['Create New Integration', 'Create a Project'],
    ["{name: /Integration Name/}", "{name: /Integration name/}"],
    ["{name: /Project Name/}", "{name: /Project name/}"],
    ["{name: 'Create Integration'}", "{name: 'Create', exact: true}"],
  ],
  // Runtimes register under default-project unless the project is linked to a cloud project
  '08-verify-icp.sh': [
    ['ICP_PROJECT=$(echo "$PROJECT_NAME" | tr \'[:upper:]\' \'[:lower:]\')', 'ICP_PROJECT="default-project"'],
    ['"1/1 Online"', '"1/1 Active"'],
  ],
};

for (const [name, pairs] of Object.entries(replacements)) {
  const script = path.join(examplesRoot, example, name);
  if (name !== '02-create-integration.sh' && !fs.existsSync(script)) {
    continue;
  }
  let source = fs.readFileSync(script, 'utf8');
  for (const [from, to] of pairs) {
    if (!source.includes(from)) {
      throw new Error(`${script} is missing the expected text: ${from}`);
    }
    source = source.split(from).join(to);
  }
  fs.writeFileSync(script, source);
  console.log(`Aligned ${script} with the current WSO2 Integrator UI`);
}
