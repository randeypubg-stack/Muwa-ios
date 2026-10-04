import {build} from "esbuild";
await build({entryPoints:["runtime/server.ts"],bundle:true,platform:"node",target:"node22",format:"esm",packages:"external",outfile:"dist/server.mjs",sourcemap:false});
