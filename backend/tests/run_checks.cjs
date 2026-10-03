// Compile the checked-in helpers into a disposable test tree. Floot-owned auth
// and DB adapters are replaced only in these tests, never in application builds.
const fs = require("node:fs");
const path = require("node:path");
const ts = require("typescript");
const Jasmine = require("jasmine");
const root = path.resolve(__dirname, "..");
const folder = fs.mkdtempSync(path.join(root, ".test-run-"));
const databaseTests = Boolean(process.env.MUWA_TEST_DATABASE_URL);
const helpers = path.join(folder, "helpers");
fs.mkdirSync(helpers);

async function main() {
  try {
    if (databaseTests) {
      const url = new URL(process.env.MUWA_TEST_DATABASE_URL);
      if (
        !["localhost", "127.0.0.1"].includes(url.hostname) ||
        url.pathname !== "/muwa_audit"
      ) {
        throw new Error(
          "Database checks require a local disposable database named muwa_audit",
        );
      }
    }
    const names = [
      "subtitleOpenAI.tsx",
      "subtitleV2Validation.tsx",
      "subtitleOpenAI.spec.tsx",
      "subtitleV2Validation.spec.tsx",
      "adminValidation.tsx",
      "adminValidation.spec.tsx",
      "requestSecurity.tsx",
      "requestSecurity.spec.tsx",
    ];
    if (databaseTests)
      names.push(
        "premiumService.tsx",
        "adminService.tsx",
        "uploadSecurity.tsx",
        "mediaSecurity.tsx",
        "uploadCleanup.tsx",
        "telegramImport.tsx",
      );
    for (const name of names) {
      const output = ts.transpileModule(
        fs.readFileSync(path.join(root, "helpers", name), "utf8"),
        {
          fileName: name,
          reportDiagnostics: true,
          compilerOptions: {
            target: ts.ScriptTarget.ES2022,
            module: ts.ModuleKind.CommonJS,
          },
        },
      );
      if (
        output.diagnostics?.some(
          (item) => item.category === ts.DiagnosticCategory.Error,
        )
      )
        throw new Error(`Invalid TypeScript: ${name}`);
      const code = output.outputText.includes('require("@floot/storage")')
        ? output.outputText.replace(
            'require("@floot/storage")',
            'require("./testStorage")',
          )
        : output.outputText;
      fs.writeFileSync(path.join(helpers, name.replace(/\.tsx$/, ".js")), code);
    }
    if (databaseTests) {
      for (const name of [
        "publicationUpload_POST.ts",
        "publicationUpload_POST.schema.ts",
        "catalog/media_GET.ts",
        "catalog/media_GET.schema.ts",
        "diagnostics/events_POST.ts",
        "diagnostics/events_POST.schema.ts",
      ]) {
        const output = ts
          .transpileModule(
            fs.readFileSync(path.join(root, "endpoints", name), "utf8"),
            {
              fileName: name,
              compilerOptions: {
                target: ts.ScriptTarget.ES2022,
                module: ts.ModuleKind.CommonJS,
              },
            },
          )
          .outputText.replace(
            'require("@floot/storage")',
            `require(${JSON.stringify(path.join(helpers, "testStorage.js"))})`,
          );
        const destination = path.join(
          folder,
          "endpoints",
          name.replace(/\.ts$/, ".js"),
        );
        fs.mkdirSync(path.dirname(destination), { recursive: true });
        fs.writeFileSync(destination, output);
      }
      fs.copyFileSync(
        path.join(__dirname, "security-service.spec.cjs"),
        path.join(helpers, "security-service.spec.js"),
      );
    }
    if (databaseTests) {
      fs.copyFileSync(
        path.join(__dirname, "admin-service.spec.cjs"),
        path.join(helpers, "admin-service.spec.js"),
      );
      fs.copyFileSync(
        path.join(__dirname, "telegram-import.spec.cjs"),
        path.join(helpers, "telegram-import.spec.js"),
      );
      fs.writeFileSync(
        path.join(helpers, "testStorage.js"),
        `
        const {createHash}=require('node:crypto');
        const files = exports.files = new Map(), puts = exports.puts = [];
        function bytes(f) {if(f.bytes)return Buffer.from(f.bytes);const b=Buffer.alloc(f.sizeBytes);if(b.length>=4)Buffer.from([255,251,144,0]).copy(b);return b;}
        exports.upload = async o => { puts.push(o); return {ok:true,presignedUrl:'https://storage.invalid/put/'+o.filename,url:'https://storage.invalid/'+o.filename,headers:{'Content-Type':o.contentType,'Content-Length':String(o.sizeBytes),'If-None-Match':'*'}}; };
        exports.getInfo = async o => { const f=files.get(o.filename); return f?{ok:true,exists:true,sizeBytes:f.sizeBytes,etag:f.etag||'"'+createHash('sha256').update(bytes(f)).digest('hex')+'"'}:{ok:true,exists:false}; };
        exports.getUrl = async o => ({ok:true,url:'https://storage.invalid/'+o.filename});
        exports.remove = async o => {files.delete(o.filename);return {ok:true};};
        exports.listFolder = async o => ({ok:true,folders:[...new Set([...files.keys()].filter(k=>k.startsWith(o.key)).map(k=>k.split('/').slice(0,2).join('/')+'/'))],files:[]});
        exports.installFetch = () => {const original=global.fetch;global.fetch=async (url,options)=>{
          if(new URL(url).hostname!=='storage.invalid')return original(url,options);
          const key=new URL(url).pathname.slice(1),f=files.get(key);if(!f)return new Response(null,{status:404});
          const info=await exports.getInfo({filename:key});if(options?.headers?.['If-Match']&&options.headers['If-Match']!==info.etag)return new Response(null,{status:412});
          return new Response(bytes(f),{headers:{'Content-Length':String(f.sizeBytes)}});
        };return ()=>{global.fetch=original};};
      `,
      );
      fs.copyFileSync(
        path.join(__dirname, "premium-service.spec.cjs"),
        path.join(helpers, "premium-service.spec.js"),
      );
      fs.writeFileSync(
        path.join(helpers, "db.js"),
        `
        const {Kysely, CamelCasePlugin} = require('kysely');
        const {PostgresJSDialect} = require('kysely-postgres-js');
        const postgres = require('postgres');
        const {Pool} = require('pg');
        const pool = new Pool({connectionString: process.env.MUWA_TEST_DATABASE_URL, max: 12});
        exports.db = new Kysely({dialect: new PostgresJSDialect({postgres:postgres(process.env.MUWA_TEST_DATABASE_URL,{prepare:false,max:12})}), plugins: [new CamelCasePlugin()]});
        exports.testPool = pool;
      `,
      );
      fs.writeFileSync(
        path.join(helpers, "getSetServerSession.js"),
        `
        exports.NotAuthenticatedError = class NotAuthenticatedError extends Error {};
        exports.setServerSession = async () => {};
      `,
      );
      fs.writeFileSync(
        path.join(helpers, "getServerUserSession.js"),
        `
        const {NotAuthenticatedError} = require('./getSetServerSession');
        exports.getServerUserSession = async request => {
          const id = Number(request.headers.get('x-fixture-user'));
          if (![1,2,3].includes(id)) throw new NotAuthenticatedError();
          return {user: {id,role:id===1?"admin":"user"}, session: {lastAccessed: new Date()}};
        };
      `,
      );
    }
    const jasmine = new Jasmine({ projectBaseDir: folder });
    jasmine.exitOnCompletion = false;
    await jasmine.loadConfig({
      spec_dir: "helpers",
      spec_files: ["*.spec.js"],
      env: { random: false },
    });
    jasmine.env.addReporter({
      jasmineDone: (result) => {
        process.exitCode = result.overallStatus === "passed" ? 0 : 1;
      },
    });
    await jasmine.execute();
  } finally {
    if (databaseTests && fs.existsSync(path.join(helpers, "db.js"))) {
      const testDB = require(path.join(helpers, "db.js"));
      await testDB.db.destroy();
      await testDB.testPool.end();
    }
    fs.rmSync(folder, { recursive: true, force: true });
  }
}
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
