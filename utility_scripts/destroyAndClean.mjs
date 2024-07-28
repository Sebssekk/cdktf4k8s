import { execSync } from "child_process";

const cdktfArgs = process.argv.slice(2) || [];

execSync(`npm run destroy -- ${cdktfArgs.join(' ')}`,{stdio:[0, 1, 2]});
execSync('npm run clean', {stdio:[0, 1, 2]});