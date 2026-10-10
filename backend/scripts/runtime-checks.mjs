import {build} from 'esbuild';
import {mkdtemp,rm} from 'node:fs/promises';
import {spawn} from 'node:child_process';
const folder=await mkdtemp('.runtime-run-');
try {
 await build({entryPoints:['tests/runtimeChecks.ts'],bundle:true,packages:'external',platform:'node',target:'node22',format:'esm',outfile:folder+'/checks.mjs'});
 const child=spawn(process.execPath,[folder+'/checks.mjs'],{stdio:'inherit'});
 process.exitCode=await new Promise(resolve=>child.once('exit',code=>resolve(code??1)));
}finally{await rm(folder,{recursive:true,force:true});}
