#!npx tsx

import { Buffer } from 'node:buffer';
import zlib from 'node:zlib';
import * as luainjs from 'lua-in-js'; // Import lua-in-js

/* cspell: disable-next-line */
const blueprint = '0eNqFkNFuwyAMRf/Fz1CVNEkbfmWqKsq8zCqBDMjWKOLfC+kWTXvZk2Xr+t5jL3A1E46ebAS5AGlnA8iXBQL1Vpkyi/OIIIEiDsDAqqF0xvUUImmu3zFE7vFjyhU9JAZkX/EOUqQzA7SRIuHTc23mi52Ga1ZK8b8bg9GFbOBsIcmmvN63u4bBDLIRYtfkuG/15Y1MXnkm/SBsCb1RIXw5fwt8uO1FNtZuKjdXiW3yapOPymccg1xpjQa9is7/WTykczlwfYv89UUGn5liJa5Ooj521fFUd4e2a1N6AM6rems=';

/* cspell: disable-next-line */
const oneLevelProductionLine = 'eNrdV02PmzAQ/SsrzibiI2RTVVx66K2XvVYVcsC76y5gZEy2UcR/7/gzNiFRu7c2hwSP7efxm3nDpGEPLatx+1CV57rF41hG31hD2gjRpow6+Vjt0n2E2HtPeBnVHf45dQ3mETrAxrcKlqXmkTMmHMoXadIoejaFQd+QX2WCetyRMhpwfMQ9bujUZWv4NZt6AeADe4eZ7PFToj6A8sJJQ0kvxvL8PRo4E6yPG9YzHv0ozwbctyJxGsBGBekihDuFm2xSNAosSJnN6HskqMA9eBIPLdguOAv7OlLhI3WsFaSPXyQNF5zAalCe24k2DiZLN9tsXzym9vvRR31lIsbUu6A1/DUWMDeS1sLo0TrKfuMhyO/MocwICG6mWofAhjFmv2jjkbew3yKP9sPk05jKC9f8BKO2ZS8cD6+0jsfpMAoeBOfOmvWzktQ7Q8XCQgWBCXblxr/c7ZxR/UrbhpO+PD9tXcY/kZoORKf80/Z+tutzuNlRW/cKSytlPWT+M64F4yd3wlc9jhwkF7RuSYzrmrQE7s143L0lqcUHiVBxcjfZFoiAyF5OZZptjZjGgRCp4JZ2FFxAoPipJUDLjMjzM1EB1msS59sRQGFYs36cukH5CpOsbSf9DPzg4SPb1I5KMIip0r2b2iRJanw300WxT8wV3DozBavhpprTbJOZx0rf0DM0hAxqPKMDwdKt8uyqlzJYog9mtMpqYkndKo8AvDuwcosGwisbQJnb3riSh0FdkUm1Rrx/0cRmR3CNxL9DAhl5wCOpBAVvU6R+gIILMRcBuBxY4ZEeZf32JbAq4zn0RGat74zK4kXJVmMbgYVVh8Ez+lHPMv8a7sSF3R4szTN62q1LcmclmSJXQqGCxmuleanMsJrui91fCVVBvzP+Nt6TZ+7Umfxb4kx34adYZvC1Qq0+080VsX5y3ZxWEb+e/S+VnK8JuVjFdgrZ3uNtNZ2VYkOlBgoNlZmlC4gVld5bY/xYWXKrCGl5zrLzCPzYFXkIgOG9LKpF9xqq2rD7isdKv9sFnwhih59EKoHc6GneyOm6pTnidiIyHq6fUMtMMdGz+RyWzPRD9dDj9erO17wul4CqOywr1GGC1gVa6LJA9tEgewYFU5iyRjUht7uNS9P9pw1JbQqez0rup2hulWyh14X7B4KCVnJZfn8ETd/tumxaiLB/CJqH2Ss4syf8OShTs/5/pNYEf15mxMnIJl7ramHS8kj4qF8r+nW1z2VSg8MCJsrzxyu/PE4KQIpjZ7pa8PUzJ2Li/UP1mfTNb+082u0=';

/* cspell: disable-next-line */
const twoLevelProductionLine = 'eNrdWE2PozgQ/SstziYC8tG9anGZw9720tfRCDlQ3e2JwciYdEcR/30L/IEhJJMZaVeaySW4jMvl5/eenRTigYuc8ocsPeecNk0a/CMK4AFhRRqU/WO2i58CIj4qkGmQl/R7WxZUBmSPAw8ZvpaYRymEclm+9CGdRffG2KgK+EwjUtES0qCm4ZFWtGBtmSzlz0VbqTQmtfjAnuTxr2j4YJY3CQWDSjXp+WtQS6FEFRaiEjL4lp5Ncj9K1KnGGFNQBoSWQ95oFZNGUQVp0pGvgWKKVlhJWHOMjXlm8eVMWz9TKbiCKnzrYRjzTKImyytvWeHSbCM/y7tQIWXegmzgh2MRmQa4HaZby6OScVRHELCizTWkdltC8ckKD4xZ/BoYrKpbH5a4X1AuT9jiXLxJWr+zPGzafaPkBOwb7yzPFcXeHAO2NtUE6MmoR1Pf2o3sSP7OeCGhSs8vG8fgF8hZDZrCL5vb7NXzSDMit+VtLaxMVMjkV5orIU9uhr91O3AppWI5h5DmOXDAdQsZlocotvmR8kyd3Eo2WwIomrdTGicbI46mBihwKs5KhiUQVHDLAWHpCLy+wrDB+p3I1XbEpNjMRdW0ZT3Uip2C81Y/Iz60/pVhw4hMCdzTQceuaxVFsanddG+3T5FZgnvPdOHbuFKNabJKzGOmV+gFCoB6aHdkD7QvKz07NxoCFui9aS2iGllQN0NFmLzci3RDapCZ3cCe21476ydDn+hJtQS8v9DIsmOyjMhfQ4SM3NMGMsWw2pgMXwjBCMwoAMeBBRzZsfdjXwKLMu6mlfSs9YsZWDyz4KFtd2AW1dvgBf1dTxJ/GW7GWdxO3Ic7c7gk10+WxGozJs4r0SrDJc+1Ev3RcXNxzPz2tn63PS7a4m7ZFndzW7wDegf0T1jjkOhDyENzyxDXzg+j38sO4930s517xqUnWkdcT9S79qW7/iONcL3kg9vF3CZn7OccBe6b2MS8pqa1ZFgLZrW97rdaBahFilpSmW9cvUInc7UVZ9UBiaVkC5cjeuZrLN5pk+mLzCvlDRCx/w49C2GU+gFOTulHyltIH0dH0LKbwnQPIrcxQOqXtJfxvkXrQAvF7bKPjqIuoFlqtM9g8Nm50r9NLOu6BdyvBptwmfz3kdLKqvPo3U1pBp81RWss0NLsIaO3qptvuj79xq32fnVNnfNi6weS+Du/dHcfaDC/ums+4OTu3nzJlnXX3SDIvef+SJjlU16HL4mzmxNnNyPObkqc67fn8UfhvRfs/5FM5D+l/F1UNVcs7LBXLSxrcv3piIRGtDLXPm54eATZaBvRd4Cndc9irFxhR3r+9QO2n65nfK+Gnfm5hkU/m38qMmw8Zytd9MrWbALDvxAre3Oxvc8SVCurh+wZquJf5PcOtg==';

function decode(input: string): string {
  let coded = input;
  if (input.startsWith('0')) {
    coded = input.slice(1);
  }
  
  const buffer = Buffer.from(coded, 'base64');
  return zlib.inflateSync(buffer).toString('utf-8');
}

function b64Decode(input: string): string {
  return Buffer.from(input, 'base64').toString('utf-8');
}

function getLuaResult(input: string) {
  const luaEnv = luainjs.createEnv();
  const luaScript = luaEnv.parse(input);
  const result = luaScript.exec();
  return result as luainjs.Table;
}

// biome-ignore lint/suspicious/noExplicitAny: <explanation>
function getSummary(line: any): luainjs.Table {
  return line.get('block_root').get('summary');
}

type Factory = {
  name: string;
  count: number;
}

function getFactories(summary: luainjs.Table): Factory[] {
  const result = [];
  const factories = summary?.get('factories') as luainjs.Table;

  for (const entry of Object.entries(factories.strValues)) {
    const name = entry[0];
    const info = entry[1] as luainjs.Table;
    const count = info.get('count') as number;

    result.push({ name, count });
  }

  return result;
}

function createBlueprint(factories: Factory[]) {
  const filters = factories.filter(f => f.count > 0).map((factory, index) => ({
    index: index + 1,
    name: factory.name,
    count: factory.count - 1,
  }));

  return {
    "blueprint": {
      "icons": [
        {
          "signal": {
            "type": "item",
            "name": "logistic-chest-requester"
          },
          "index": 1
        }
      ],
      "entities": [
        {
          "entity_number": 1,
          "name": "logistic-chest-requester",
          "position": {
            "x": 0,
            "y": 0
          },
          "request_filters": filters,
        }
      ],
      "item": "blueprint",
      "version": 281479278493696
    }
  }
}

// biome-ignore lint/suspicious/noExplicitAny: nope
function encode(obj: any) {
  const buffer = Buffer.from(JSON.stringify(obj), 'utf-8');
  const deflated = zlib.deflateSync(buffer);
  const base64 = deflated.toString('base64');
  return `0${base64}`;
}

console.log("blueprint");
console.log(JSON.stringify(JSON.parse(decode(blueprint)), null, 2));

console.log('')
console.log('-----------')
console.log('')

// console.log("oneLevelProductionLine");
const lineDecoded = getLuaResult(decode(oneLevelProductionLine));
const summary = getSummary(lineDecoded);

// console.log(Object.keys(summary.strValues)); 
// console.log(JSON.stringify(Object.keys(summary.strValues), null, 2));
const factories = getFactories(summary);
console.log(factories);
console.log(JSON.stringify(createBlueprint(factories), null, 2));
console.log(encode(createBlueprint(factories)));