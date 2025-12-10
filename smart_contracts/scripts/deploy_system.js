const path = require("path");
const fs = require("fs");
const Web3 = require("web3");

// RPC nodo Besu
const RPC_URL = "http://localhost:8545";

// Cuenta de prueba (Test Account 1)
const PRIVATE_KEY =
  "0x8f2a55949038a9610f50fb23b5883af3b4ecb3c3bb792cbcefbd1542c692be63";

async function main() {
  const web3 = new Web3(RPC_URL);

  const account = web3.eth.accounts.privateKeyToAccount(PRIVATE_KEY);
  web3.eth.accounts.wallet.add(account);
  web3.eth.defaultAccount = account.address;

  console.log("Deploying contracts with:", account.address);

  async function deployContract(contractName, args = []) {
    const contractJsonPath = path.resolve(
      __dirname,
      "../contracts",
      `${contractName}.json`
    );
    const json = JSON.parse(fs.readFileSync(contractJsonPath, "utf8"));

    const abi = json.abi;
    const bytecode = json.evm && json.evm.bytecode && json.evm.bytecode.object;

    if (!abi || !bytecode) {
      throw new Error(
        `No se encontró abi/bytecode en ${contractName}.json. Compilaste bien?`
      );
    }

    const contract = new web3.eth.Contract(abi);

    const deployTx = contract.deploy({
      data: "0x" + bytecode,
      arguments: args,
    });

    const gas = await deployTx.estimateGas({ from: account.address });
    console.log(`Estimating gas for ${contractName}:`, gas.toString());

    const instance = await deployTx.send({
      from: account.address,
      gas,
    });

    console.log(`${contractName} deployed at:`, instance.options.address);
    return instance.options.address;
  }

  // 1) UserVerification (issuer inicial = deployer)
  const userVerificationAddress = await deployContract("UserVerification", [
    account.address,
  ]);

  // 2) VertiportManagement
  const vertiportManagementAddress = await deployContract(
    "VertiportManagement"
  );

  // 3) EVTOLManagement
  const evtolManagementAddress = await deployContract("EVTOLManagement");

  // 4) FlightReservation (inyectamos direcciones de los otros contratos)
  const flightReservationAddress = await deployContract("FlightReservation", [
    userVerificationAddress,
    vertiportManagementAddress,
    evtolManagementAddress,
  ]);

  console.log("\n=== Deployment summary ===");
  console.log("UserVerification   :", userVerificationAddress);
  console.log("VertiportManagement:", vertiportManagementAddress);
  console.log("EVTOLManagement    :", evtolManagementAddress);
  console.log("FlightReservation  :", flightReservationAddress);
}

main().catch((err) => {
  console.error("Error deploying:", err);
  process.exit(1);
});
