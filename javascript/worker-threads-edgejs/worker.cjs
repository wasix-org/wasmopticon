const { isMainThread, parentPort, threadId, workerData } = require("node:worker_threads");

function isPrime(candidate) {
  for (let divisor = 2; divisor * divisor <= candidate; divisor++) {
    if (candidate % divisor === 0) return false;
  }
  return true;
}

let count = 0;
let sum = 0;
for (let candidate = 2; candidate <= workerData.limit; candidate++) {
  if (isPrime(candidate)) {
    count++;
    sum += candidate;
  }
}

const globalWasUnset = !Object.hasOwn(globalThis, "workerProbe");
globalThis.workerProbe = "worker";
workerData.label = "worker";
parentPort.postMessage({ count, sum, isMainThread, threadId, globalWasUnset, label: workerData.label });
