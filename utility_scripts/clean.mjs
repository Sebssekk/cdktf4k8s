import 'dotenv/config'
import { rmSync, existsSync } from "fs";

const outFolderV2 = `.out-${process.env.runningLabName}`
const tempFolder = `.tmp-${process.env.runningLabName}`

if (existsSync(tempFolder)){
    console.log(`Deleting ${tempFolder}`)
    rmSync(tempFolder, {recursive: true, force:true})
}
if (existsSync(outFolderV2)){
    console.log(`Deleting ${outFolder}`)
    rmSync(outFolderV2, {recursive: true, force:true})
}
